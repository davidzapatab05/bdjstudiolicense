import { Injectable, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import {
  RegisterDeviceDto,
  BanDeviceDto,
  UpdateDeviceDto,
} from './dto/device.dto';

@Injectable()
export class DeviceService {
  private readonly logger = new Logger(DeviceService.name);

  constructor(private readonly prisma: PrismaService) {}

  async register(dto: RegisterDeviceDto) {
    const banned = await this.prisma.bannedDevice.findUnique({
      where: { deviceId: dto.deviceId },
    });

    if (banned) {
      this.logger.warn(`Banned device attempted registration: ${dto.deviceId}`);
      throw new HttpException(
        'This device has been banned',
        HttpStatus.FORBIDDEN,
      );
    }

    const existing = await this.prisma.device.findUnique({
      where: { hardwareFingerprint: dto.hardwareFingerprint },
    });

    if (existing) {
      await this.prisma.device.update({
        where: { id: existing.id },
        data: {
          lastSeen: new Date(),
          lastIp: dto.ip ?? existing.lastIp,
          name: dto.name,
          platform: dto.platform,
        },
      });
      return existing;
    }

    return this.prisma.device.create({
      data: {
        hardwareFingerprint: dto.hardwareFingerprint,
        deviceId: dto.deviceId,
        name: dto.name,
        platform: dto.platform,
        lastIp: dto.ip ?? null,
      },
    });
  }

  async getById(deviceId: string) {
    const device = await this.prisma.device.findFirst({
      where: { deviceId },
      include: {
        user: { select: { id: true, email: true, name: true } },
        license: true,
      },
    });

    if (!device) {
      throw new HttpException('Device not found', HttpStatus.NOT_FOUND);
    }

    return device;
  }

  async getByFingerprint(fingerprint: string) {
    return this.prisma.device.findUnique({
      where: { hardwareFingerprint: fingerprint },
    });
  }

  async updateLastSeen(deviceId: string) {
    await this.prisma.device.updateMany({
      where: { deviceId },
      data: { lastSeen: new Date() },
    });
  }

  async ban(dto: BanDeviceDto) {
    const device = await this.prisma.device.findFirst({
      where: { deviceId: dto.deviceId },
    });

    if (!device) {
      throw new HttpException('Device not found', HttpStatus.NOT_FOUND);
    }

    await this.prisma.bannedDevice.upsert({
      where: { deviceId: dto.deviceId },
      create: {
        deviceId: dto.deviceId,
        reason: dto.reason,
        bannedBy: dto.bannedBy ?? 'system',
      },
      update: {
        reason: dto.reason,
        bannedBy: dto.bannedBy ?? 'system',
      },
    });

    await this.prisma.device.update({
      where: { id: device.id },
      data: {
        isActive: false,
        isBanned: true,
        bannedAt: new Date(),
        banReason: dto.reason,
      },
    });

    this.logger.log(`Device banned: ${dto.deviceId} - Reason: ${dto.reason}`);

    return { success: true, message: 'Device banned successfully' };
  }

  async unban(deviceId: string) {
    await this.prisma.bannedDevice.deleteMany({
      where: { deviceId },
    });

    await this.prisma.device.updateMany({
      where: { deviceId },
      data: {
        isActive: true,
        isBanned: false,
        bannedAt: null,
        banReason: null,
      },
    });

    this.logger.log(`Device unbanned: ${deviceId}`);

    return { success: true, message: 'Device unbanned successfully' };
  }

  async getAll(page = 1, limit = 20) {
    const safePage = Number.isFinite(page) ? Math.max(1, Math.trunc(page)) : 1;
    const safeLimit = Number.isFinite(limit)
      ? Math.min(100, Math.max(1, Math.trunc(limit)))
      : 20;
    const skip = (safePage - 1) * safeLimit;

    const [devices, total] = await Promise.all([
      this.prisma.device.findMany({
        skip,
        take: safeLimit,
        include: {
          user: { select: { id: true, email: true, name: true } },
          license: { select: { licenseKey: true, status: true } },
        },
        orderBy: { lastSeen: 'desc' },
      }),
      this.prisma.device.count(),
    ]);

    return {
      data: devices,
      meta: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages: Math.ceil(total / safeLimit),
      },
    };
  }

  async update(deviceId: string, dto: UpdateDeviceDto) {
    const device = await this.prisma.device.findFirst({
      where: { deviceId },
    });

    if (!device) {
      throw new HttpException('Device not found', HttpStatus.NOT_FOUND);
    }

    return this.prisma.device.update({
      where: { id: device.id },
      data: dto,
    });
  }

  async isBanned(deviceId: string): Promise<boolean> {
    const banned = await this.prisma.bannedDevice.findUnique({
      where: { deviceId },
    });
    return !!banned;
  }
}
