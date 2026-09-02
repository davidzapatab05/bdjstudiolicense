import { Injectable, NotFoundException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  SyncCustomerDto,
  SyncOfflineDeviceBlockDto,
  SyncOfflineLicenseDto,
} from './dto/issuer.dto';

@Injectable()
export class IssuerService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async syncCustomer(dto: SyncCustomerDto, adminId: string) {
    const email = dto.email.trim().toLowerCase();
    const customer = await this.prisma.customer.upsert({
      where: { externalId: dto.externalId },
      create: { ...dto, email },
      update: { name: dto.name, email, deviceId: dto.deviceId },
    });
    await this.audit.log({
      adminId,
      action: 'sync',
      targetType: 'customer',
      targetId: customer.id,
      details: JSON.stringify({ externalId: customer.externalId }),
    });
    return customer;
  }

  async syncLicense(dto: SyncOfflineLicenseDto, adminId: string) {
    const customer = await this.prisma.customer.findUnique({
      where: { externalId: dto.customerExternalId },
    });
    if (!customer) {
      throw new NotFoundException('Customer must be synchronized first');
    }
    const license = await this.prisma.offlineLicense.upsert({
      where: { externalId: dto.externalId },
      create: {
        externalId: dto.externalId,
        customerId: customer.id,
        product: dto.product,
        deviceId: dto.deviceId,
        plan: dto.plan,
        tokenDigest: dto.tokenDigest,
        issuedAt: dto.issuedAt,
        expiresAt: dto.expiresAt,
        status: dto.status ?? 'active',
      },
      update: {
        customerId: customer.id,
        product: dto.product,
        deviceId: dto.deviceId,
        plan: dto.plan,
        tokenDigest: dto.tokenDigest,
        issuedAt: dto.issuedAt,
        expiresAt: dto.expiresAt,
        status: dto.status ?? 'active',
      },
    });
    await this.audit.log({
      adminId,
      action: 'sync',
      targetType: 'offline_license',
      targetId: license.id,
      details: JSON.stringify({
        externalId: license.externalId,
        product: license.product,
        status: license.status,
      }),
    });
    return license;
  }

  async snapshot() {
    const [customers, licenses, deviceBlocks] = await Promise.all([
      this.prisma.customer.findMany({ orderBy: { updatedAt: 'asc' } }),
      this.prisma.offlineLicense.findMany({
        include: { customer: { select: { externalId: true } } },
        orderBy: { updatedAt: 'asc' },
      }),
      this.prisma.offlineDeviceBlock.findMany({
        orderBy: { updatedAt: 'asc' },
      }),
    ]);
    return { customers, licenses, deviceBlocks };
  }

  async syncDeviceBlock(dto: SyncOfflineDeviceBlockDto, adminId: string) {
    const block = await this.prisma.offlineDeviceBlock.upsert({
      where: { deviceId: dto.deviceId },
      create: dto,
      update: { reason: dto.reason, blockedAt: dto.blockedAt },
    });
    await this.audit.log({
      adminId,
      action: 'block',
      targetType: 'offline_device',
      targetId: block.id,
    });
    return block;
  }

  async removeDeviceBlock(deviceId: string, adminId: string) {
    const block = await this.prisma.offlineDeviceBlock.findUnique({
      where: { deviceId },
    });
    if (block) {
      await this.prisma.offlineDeviceBlock.delete({ where: { id: block.id } });
      await this.audit.log({
        adminId,
        action: 'unblock',
        targetType: 'offline_device',
        targetId: block.id,
      });
    }
    return { success: true };
  }

  async removeCustomer(externalId: string, adminId: string) {
    const customer = await this.prisma.customer.findUnique({
      where: { externalId },
    });
    if (customer) {
      await this.prisma.offlineLicense.deleteMany({
        where: { customerId: customer.id },
      });
      await this.prisma.customer.delete({ where: { id: customer.id } });
      await this.audit.log({
        adminId,
        action: 'delete',
        targetType: 'customer',
        targetId: customer.id,
        details: JSON.stringify({ externalId }),
      });
    }
    return { success: true };
  }

  async removeLicense(externalId: string, adminId: string) {
    const license = await this.prisma.offlineLicense.findUnique({
      where: { externalId },
    });
    if (license) {
      await this.prisma.offlineLicense.delete({ where: { id: license.id } });
      await this.audit.log({
        adminId,
        action: 'delete',
        targetType: 'offline_license',
        targetId: license.id,
        details: JSON.stringify({ externalId }),
      });
    }
    return { success: true };
  }
}
