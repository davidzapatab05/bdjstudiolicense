import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface LogActionParams {
  adminId: string;
  action: string;
  targetType: string;
  targetId?: string;
  details?: string;
  ip?: string;
}

@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async log(params: LogActionParams) {
    const entry = await this.prisma.auditLog.create({
      data: {
        adminId: params.adminId,
        action: params.action,
        targetType: params.targetType,
        targetId: params.targetId ?? null,
        details: params.details ?? null,
        ip: params.ip ?? null,
      },
    });

    this.logger.log(
      `AUDIT: [${params.action}] ${params.targetType} ${params.targetId ?? ''} by ${params.adminId}`,
    );

    return entry;
  }

  async getLogs(page = 1, limit = 50) {
    const { safePage, safeLimit, skip } = this.pagination(page, limit);

    const [logs, total] = await Promise.all([
      this.prisma.auditLog.findMany({
        skip,
        take: safeLimit,
        include: {
          admin: { select: { id: true, email: true, name: true } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.auditLog.count(),
    ]);

    return {
      data: logs,
      meta: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages: Math.ceil(total / safeLimit),
      },
    };
  }

  async getLogsByAdmin(adminId: string, page = 1, limit = 50) {
    const { safePage, safeLimit, skip } = this.pagination(page, limit);

    const [logs, total] = await Promise.all([
      this.prisma.auditLog.findMany({
        where: { adminId },
        skip,
        take: safeLimit,
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.auditLog.count({ where: { adminId } }),
    ]);

    return {
      data: logs,
      meta: {
        total,
        page: safePage,
        limit: safeLimit,
        totalPages: Math.ceil(total / safeLimit),
      },
    };
  }

  async getLogsByTarget(targetType: string, targetId: string) {
    return this.prisma.auditLog.findMany({
      where: { targetType, targetId },
      include: {
        admin: { select: { id: true, email: true, name: true } },
      },
      orderBy: { createdAt: 'desc' },
    });
  }

  private pagination(page: number, limit: number) {
    const safePage = Number.isFinite(page) ? Math.max(1, Math.trunc(page)) : 1;
    const safeLimit = Number.isFinite(limit)
      ? Math.min(100, Math.max(1, Math.trunc(limit)))
      : 50;
    return { safePage, safeLimit, skip: (safePage - 1) * safeLimit };
  }
}
