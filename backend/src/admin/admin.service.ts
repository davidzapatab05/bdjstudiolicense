import { Injectable, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuditService } from '../audit/audit.service';
import * as bcrypt from 'bcrypt';
import {
  CreateAdminDto,
  UpdateAdminDto,
  CreateLicensePlanDto,
  UpdateLicensePlanDto,
  CreateAppVersionDto,
} from './dto/admin.dto';

@Injectable()
export class AdminService {
  private readonly logger = new Logger(AdminService.name);
  private readonly SALT_ROUNDS = 12;

  constructor(
    private readonly prisma: PrismaService,
    private readonly auditService: AuditService,
  ) {}

  private csvValue(
    value: string | number | boolean | null | undefined,
  ): string {
    const text = String(value ?? '');
    // Evita que Excel/LibreOffice interpreten datos controlados por usuarios
    // como fórmulas al abrir una exportación administrativa.
    const formulaSafe = /^[=+\-@]/.test(text) ? `'${text}` : text;
    return `"${formulaSafe.replaceAll('"', '""')}"`;
  }

  // ==================== ADMIN USERS ====================

  async createAdmin(dto: CreateAdminDto, adminId?: string) {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.prisma.adminUser.findUnique({
      where: { email },
    });

    if (existing) {
      throw new HttpException(
        'Admin email already exists',
        HttpStatus.CONFLICT,
      );
    }

    const hashedPassword = await bcrypt.hash(dto.password, this.SALT_ROUNDS);

    const admin = await this.prisma.adminUser.create({
      data: {
        email,
        password: hashedPassword,
        name: dto.name,
        role: 'super',
      },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        isActive: true,
        createdAt: true,
      },
    });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'create',
        targetType: 'admin',
        targetId: admin.id,
        details: JSON.stringify({ email, role: 'super' }),
      });
    }

    return admin;
  }

  async getAdmins() {
    return this.prisma.adminUser.findMany({
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        isActive: true,
        createdAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  async toggleAdmin(id: string, adminId?: string) {
    if (id === adminId) {
      throw new HttpException(
        'An administrator cannot deactivate their own account',
        HttpStatus.BAD_REQUEST,
      );
    }
    const admin = await this.prisma.adminUser.findUnique({ where: { id } });
    if (!admin) {
      throw new HttpException('Admin not found', HttpStatus.NOT_FOUND);
    }

    const updated = await this.prisma.adminUser.update({
      where: { id },
      data: { isActive: !admin.isActive },
    });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: updated.isActive ? 'activate' : 'deactivate',
        targetType: 'admin',
        targetId: id,
        details: JSON.stringify({ email: admin.email }),
      });
    }

    return updated;
  }

  async updateAdmin(id: string, dto: UpdateAdminDto, adminId?: string) {
    const admin = await this.prisma.adminUser.findUnique({ where: { id } });
    if (!admin) {
      throw new HttpException('Admin not found', HttpStatus.NOT_FOUND);
    }
    const email = dto.email?.trim().toLowerCase();
    if (email && email !== admin.email) {
      const existing = await this.prisma.adminUser.findUnique({
        where: { email },
      });
      if (existing) {
        throw new HttpException(
          'Admin email already exists',
          HttpStatus.CONFLICT,
        );
      }
    }
    const updated = await this.prisma.adminUser.update({
      where: { id },
      data: {
        ...(email == null ? {} : { email }),
        ...(dto.name == null ? {} : { name: dto.name.trim() }),
        ...(dto.password == null
          ? {}
          : { password: await bcrypt.hash(dto.password, this.SALT_ROUNDS) }),
      },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        isActive: true,
        createdAt: true,
      },
    });
    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'update',
        targetType: 'admin',
        targetId: id,
        details: JSON.stringify({ email: updated.email }),
      });
    }
    return updated;
  }

  async deleteAdmin(id: string, adminId?: string) {
    if (id === adminId) {
      throw new HttpException(
        'An administrator cannot delete their own account',
        HttpStatus.BAD_REQUEST,
      );
    }
    const admin = await this.prisma.adminUser.findUnique({ where: { id } });
    if (!admin) {
      throw new HttpException('Admin not found', HttpStatus.NOT_FOUND);
    }
    await this.prisma.adminUser.delete({ where: { id } });
    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'delete',
        targetType: 'admin',
        targetId: id,
        details: JSON.stringify({ email: admin.email }),
      });
    }
    return { deleted: true, id };
  }

  // ==================== DASHBOARD ====================

  async getDashboard() {
    const [
      totalUsers,
      totalLicenses,
      activeLicenses,
      totalDevices,
      activeDevices,
      bannedDevices,
      recentActivations,
    ] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.license.count(),
      this.prisma.license.count({ where: { status: 'active' } }),
      this.prisma.device.count(),
      this.prisma.device.count({ where: { isActive: true } }),
      this.prisma.device.count({ where: { isBanned: true } }),
      this.prisma.activation.findMany({
        take: 10,
        orderBy: { createdAt: 'desc' },
        include: {
          license: { select: { licenseKey: true } },
        },
      }),
    ]);

    return {
      stats: {
        totalUsers,
        totalLicenses,
        activeLicenses,
        totalDevices,
        activeDevices,
        bannedDevices,
      },
      recentActivations,
    };
  }

  // ==================== LICENSE PLANS ====================

  async createPlan(dto: CreateLicensePlanDto, adminId?: string) {
    const plan = await this.prisma.licensePlan.create({
      data: {
        name: dto.name,
        type: dto.type,
        price: dto.price,
        maxDevices: dto.maxDevices ?? 1,
        features: dto.features ?? '[]',
      },
    });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'create',
        targetType: 'plan',
        targetId: plan.id,
        details: JSON.stringify({
          name: dto.name,
          type: dto.type,
          price: dto.price,
        }),
      });
    }

    return plan;
  }

  async getPlans() {
    return this.prisma.licensePlan.findMany({
      include: { _count: { select: { licenses: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async updatePlan(id: string, dto: UpdateLicensePlanDto, adminId?: string) {
    const plan = await this.prisma.licensePlan.findUnique({ where: { id } });
    if (!plan) {
      throw new HttpException('Plan not found', HttpStatus.NOT_FOUND);
    }

    const updated = await this.prisma.licensePlan.update({
      where: { id },
      data: dto,
    });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'update',
        targetType: 'plan',
        targetId: id,
        details: JSON.stringify(dto),
      });
    }

    return updated;
  }

  async deletePlan(id: string, adminId?: string) {
    const plan = await this.prisma.licensePlan.findUnique({ where: { id } });
    if (!plan) {
      throw new HttpException('Plan not found', HttpStatus.NOT_FOUND);
    }

    const licenseCount = await this.prisma.license.count({
      where: { planId: id },
    });

    if (licenseCount > 0) {
      throw new HttpException(
        'Cannot delete plan with active licenses',
        HttpStatus.BAD_REQUEST,
      );
    }

    await this.prisma.licensePlan.delete({ where: { id } });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'delete',
        targetType: 'plan',
        targetId: id,
        details: JSON.stringify({ name: plan.name }),
      });
    }

    return { success: true, message: 'Plan deleted' };
  }

  // ==================== APP VERSIONS ====================

  async createVersion(dto: CreateAppVersionDto, adminId?: string) {
    const version = await this.prisma.appVersion.create({ data: dto });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'create',
        targetType: 'version',
        targetId: version.id,
        details: JSON.stringify({
          version: dto.version,
          platform: dto.platform,
        }),
      });
    }

    return version;
  }

  async getVersions(platform?: string) {
    const where = platform ? { platform } : {};
    return this.prisma.appVersion.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });
  }

  async getLatestVersion(platform: string) {
    return this.prisma.appVersion.findFirst({
      where: { platform },
      orderBy: { createdAt: 'desc' },
    });
  }

  // ==================== USERS MANAGEMENT ====================

  async getUsers(page = 1, limit = 20) {
    const safePage = Number.isFinite(page) ? Math.max(1, Math.trunc(page)) : 1;
    const safeLimit = Number.isFinite(limit)
      ? Math.min(100, Math.max(1, Math.trunc(limit)))
      : 20;
    const skip = (safePage - 1) * safeLimit;

    const [users, total] = await Promise.all([
      this.prisma.user.findMany({
        skip,
        take: safeLimit,
        select: {
          id: true,
          email: true,
          name: true,
          displayName: true,
          role: true,
          isVerified: true,
          createdAt: true,
          _count: { select: { licenses: true, devices: true } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.user.count(),
    ]);

    return {
      data: users,
      meta: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages: Math.ceil(total / safeLimit),
      },
    };
  }

  async suspendUser(id: string, adminId?: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }

    await this.prisma.device.updateMany({
      where: { userId: id },
      data: { isActive: false },
    });

    await this.prisma.license.updateMany({
      where: { userId: id },
      data: { status: 'inactive' },
    });

    this.logger.log(`User suspended: ${id}`);

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'suspend',
        targetType: 'user',
        targetId: id,
        details: JSON.stringify({ email: user.email }),
      });
    }

    return { success: true, message: 'User suspended' };
  }

  async deleteUser(id: string, adminId?: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }

    await this.prisma.device.deleteMany({ where: { userId: id } });
    await this.prisma.license.deleteMany({ where: { userId: id } });
    await this.prisma.user.delete({ where: { id } });

    this.logger.log(`User deleted: ${id}`);

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: 'delete',
        targetType: 'user',
        targetId: id,
        details: JSON.stringify({ email: user.email }),
      });
    }

    return { success: true, message: 'User deleted' };
  }

  // ==================== FEATURE FLAGS ====================

  async getFeatureFlags() {
    return this.prisma.featureFlag.findMany({
      orderBy: { name: 'asc' },
    });
  }

  async toggleFeatureFlag(id: string, adminId?: string) {
    const flag = await this.prisma.featureFlag.findUnique({ where: { id } });
    if (!flag) {
      throw new HttpException('Feature flag not found', HttpStatus.NOT_FOUND);
    }

    const updated = await this.prisma.featureFlag.update({
      where: { id },
      data: { enabled: !flag.enabled },
    });

    if (adminId) {
      await this.auditService.log({
        adminId,
        action: updated.enabled ? 'enable' : 'disable',
        targetType: 'feature_flag',
        targetId: id,
        details: JSON.stringify({ name: flag.name }),
      });
    }

    return updated;
  }

  // ==================== EXPORT REPORTS ====================

  async exportUsersCsv(): Promise<string> {
    const users = await this.prisma.user.findMany({
      select: {
        id: true,
        email: true,
        name: true,
        displayName: true,
        role: true,
        isVerified: true,
        createdAt: true,
        _count: { select: { licenses: true, devices: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    const header =
      'ID,Email,Name,Display Name,Role,Verified,Licenses,Devices,Created At\n';
    const rows = users
      .map((u) =>
        [
          u.id,
          u.email,
          u.name,
          u.displayName,
          u.role,
          u.isVerified,
          u._count.licenses,
          u._count.devices,
          u.createdAt.toISOString(),
        ]
          .map((value) => this.csvValue(value))
          .join(','),
      )
      .join('\n');

    return header + rows;
  }

  async exportLicensesCsv(): Promise<string> {
    const licenses = await this.prisma.license.findMany({
      include: {
        user: { select: { email: true } },
        plan: { select: { name: true } },
        _count: { select: { devices: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    const header =
      'ID,Key,Status,Type,Max Devices,User Email,Plan,Active Devices,Expires At,Created At\n';
    const rows = licenses
      .map((l) =>
        [
          l.id,
          l.licenseKey,
          l.status,
          l.type,
          l.maxDevices,
          l.user?.email ?? 'unassigned',
          l.plan?.name ?? 'none',
          l._count.devices,
          l.expiresAt?.toISOString() ?? 'never',
          l.createdAt.toISOString(),
        ]
          .map((value) => this.csvValue(value))
          .join(','),
      )
      .join('\n');

    return header + rows;
  }

  async exportActivationsCsv(): Promise<string> {
    const activations = await this.prisma.activation.findMany({
      include: {
        license: { select: { licenseKey: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: 1000,
    });

    const header = 'ID,License Key,Device ID,Success,IP,Platform,Created At\n';
    const rows = activations
      .map((a) =>
        [
          a.id,
          a.license.licenseKey,
          a.deviceId,
          a.success,
          a.ip,
          a.platform,
          a.createdAt.toISOString(),
        ]
          .map((value) => this.csvValue(value))
          .join(','),
      )
      .join('\n');

    return header + rows;
  }
}
