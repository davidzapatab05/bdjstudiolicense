import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  SetMetadata,
} from '@nestjs/common';
import { AuditService } from './audit.service';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';

const Roles = (...roles: string[]) => SetMetadata('roles', roles);

@Controller({ path: 'audit', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('super')
export class AuditController {
  constructor(private readonly auditService: AuditService) {}

  @Get()
  async getLogs(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.auditService.getLogs(
      page ? Number.parseInt(page, 10) : 1,
      limit ? Number.parseInt(limit, 10) : 50,
    );
  }

  @Get('admin/:adminId')
  async getLogsByAdmin(
    @Param('adminId') adminId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.auditService.getLogsByAdmin(
      adminId,
      page ? Number.parseInt(page, 10) : 1,
      limit ? Number.parseInt(limit, 10) : 50,
    );
  }

  @Get('target/:targetType/:targetId')
  async getLogsByTarget(
    @Param('targetType') targetType: string,
    @Param('targetId') targetId: string,
  ) {
    return this.auditService.getLogsByTarget(targetType, targetId);
  }
}
