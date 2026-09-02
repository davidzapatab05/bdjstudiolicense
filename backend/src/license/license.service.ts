import { Injectable, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  ActivateLicenseDto,
  ValidateLicenseDto,
  RevokeLicenseDto,
  CreateLicenseDto,
  GenerateBatchDto,
} from './dto/license.dto';
import * as crypto from 'node:crypto';

@Injectable()
export class LicenseService {
  private readonly logger = new Logger(LicenseService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Busca una licencia por su clave y valida que exista, no esté revocada
   * y no haya expirado. Centraliza la lógica compartida por activate/validate.
   */
  private async findValidLicenseOrThrow(licenseKey: string) {
    const license = await this.prisma.license.findUnique({
      where: { licenseKey },
      include: { plan: true, devices: true },
    });

    if (!license) {
      throw new HttpException('License not found', HttpStatus.NOT_FOUND);
    }

    if (license.status === 'revoked') {
      throw new HttpException('License has been revoked', HttpStatus.FORBIDDEN);
    }

    if (license.expiresAt && new Date(license.expiresAt) < new Date()) {
      throw new HttpException('License has expired', HttpStatus.FORBIDDEN);
    }

    return license;
  }

  async activate(dto: ActivateLicenseDto, sourceIp?: string) {
    const license = await this.findValidLicenseOrThrow(dto.licenseKey);
    const bannedDevice = await this.prisma.bannedDevice.findFirst({
      where: {
        OR: [{ deviceId: dto.deviceId }, { deviceId: dto.hardwareFingerprint }],
      },
    });
    if (bannedDevice) {
      throw new HttpException(
        'This device has been banned',
        HttpStatus.FORBIDDEN,
      );
    }

    const activeDevices = license.devices.filter((d) => d.isActive);
    const existingDevice = activeDevices.find(
      (d) => d.hardwareFingerprint === dto.hardwareFingerprint,
    );

    if (!existingDevice && activeDevices.length >= license.maxDevices) {
      throw new HttpException(
        `Maximum devices (${license.maxDevices}) reached for this license`,
        HttpStatus.FORBIDDEN,
      );
    }

    let device;
    if (existingDevice) {
      device = await this.prisma.device.update({
        where: { id: existingDevice.id },
        data: {
          lastSeen: new Date(),
          lastIp: sourceIp ?? null,
          isActive: true,
        },
      });
    } else {
      device = await this.prisma.device.create({
        data: {
          hardwareFingerprint: dto.hardwareFingerprint,
          deviceId: dto.deviceId,
          name: dto.deviceName ?? `Device-${dto.platform}`,
          platform: dto.platform,
          lastIp: sourceIp ?? null,
          isActive: true,
          userId: license.userId ?? null,
          licenseId: license.id,
        },
      });
    }

    await this.prisma.activation.create({
      data: {
        licenseId: license.id,
        deviceId: device.deviceId,
        success: true,
        ip: sourceIp ?? null,
        platform: dto.platform,
      },
    });

    if (license.status === 'inactive') {
      await this.prisma.license.update({
        where: { id: license.id },
        data: {
          status: 'active',
          activatedAt: new Date(),
        },
      });
    }

    this.logger.log(
      `License activated: ${dto.licenseKey} for device ${dto.deviceId}`,
    );

    return {
      success: true,
      licenseKey: license.licenseKey,
      status: 'active',
      maxDevices: license.maxDevices,
      expiresAt: license.expiresAt,
      offlineDays: license.offlineDays,
      deviceName: device.name,
    };
  }

  async validate(dto: ValidateLicenseDto) {
    const license = await this.findValidLicenseOrThrow(dto.licenseKey);

    const device = license.devices.find(
      (d) => d.hardwareFingerprint === dto.hardwareFingerprint,
    );

    if (!device?.isActive) {
      throw new HttpException('Device not authorized', HttpStatus.FORBIDDEN);
    }

    return {
      valid: true,
      licenseKey: license.licenseKey,
      status: license.status,
      plan: license.plan?.name ?? 'default',
      expiresAt: license.expiresAt,
      offlineDays: license.offlineDays,
    };
  }

  async revoke(dto: RevokeLicenseDto) {
    const license = await this.prisma.license.findUnique({
      where: { licenseKey: dto.licenseKey },
    });

    if (!license) {
      throw new HttpException('License not found', HttpStatus.NOT_FOUND);
    }

    await this.prisma.license.update({
      where: { id: license.id },
      data: { status: 'revoked' },
    });

    await this.prisma.device.updateMany({
      where: { licenseId: license.id },
      data: { isActive: false },
    });

    this.logger.log(
      `License revoked: ${dto.licenseKey} - Reason: ${dto.reason ?? 'N/A'}`,
    );

    return { success: true, message: 'License revoked successfully' };
  }

  async create(dto: CreateLicenseDto) {
    const licenseKey = this.generateLicenseKey();

    const license = await this.prisma.license.create({
      data: {
        licenseKey,
        userId: dto.userId ?? null,
        planId: dto.planId ?? null,
        maxDevices: dto.maxDevices ?? 1,
        type: dto.type ?? 'perpetual',
        status: 'inactive',
      },
      include: { plan: true },
    });

    const userSuffix = dto.userId ? ` for user ${dto.userId}` : '';
    this.logger.log(`License created: ${licenseKey}${userSuffix}`);

    return license;
  }

  async generateBatch(dto: GenerateBatchDto) {
    const data = Array.from({ length: dto.count }, () => ({
      licenseKey: this.generateLicenseKey(),
      planId: dto.planId ?? null,
      maxDevices: dto.maxDevices ?? 1,
      type: 'perpetual',
      status: 'inactive',
    }));

    const createOps = data.map((item) =>
      this.prisma.license.create({ data: item }),
    );

    const licenses = await this.prisma.$transaction(createOps);

    this.logger.log(`Generated ${dto.count} license keys in batch transaction`);

    return {
      count: licenses.length,
      licenses: licenses.map((l) => ({
        id: l.id,
        licenseKey: l.licenseKey,
        status: l.status,
      })),
    };
  }

  async getAll(page = 1, limit = 20) {
    const safePage = Number.isFinite(page) ? Math.max(1, Math.trunc(page)) : 1;
    const safeLimit = Number.isFinite(limit)
      ? Math.min(100, Math.max(1, Math.trunc(limit)))
      : 20;
    const skip = (safePage - 1) * safeLimit;

    const [licenses, total] = await Promise.all([
      this.prisma.license.findMany({
        skip,
        take: safeLimit,
        include: {
          plan: true,
          devices: true,
          user: { select: { id: true, email: true, name: true } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.license.count(),
    ]);

    return {
      data: licenses,
      meta: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages: Math.ceil(total / safeLimit),
      },
    };
  }

  async getById(id: string) {
    const license = await this.prisma.license.findUnique({
      where: { id },
      include: {
        plan: true,
        devices: true,
        activations: true,
        user: { select: { id: true, email: true, name: true } },
      },
    });

    if (!license) {
      throw new HttpException('License not found', HttpStatus.NOT_FOUND);
    }

    return license;
  }

  async getActivations(licenseKey: string) {
    const license = await this.prisma.license.findUnique({
      where: { licenseKey },
      include: { activations: { orderBy: { createdAt: 'desc' } } },
    });

    if (!license) {
      throw new HttpException('License not found', HttpStatus.NOT_FOUND);
    }

    return license.activations;
  }

  private generateLicenseKey(): string {
    const segment = () => crypto.randomBytes(2).toString('hex').toUpperCase();
    return `SPP-${segment()}-${segment()}-${segment()}`;
  }
}
