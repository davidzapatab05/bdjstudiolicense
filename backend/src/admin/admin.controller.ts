import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Body,
  Param,
  Query,
  UseGuards,
  Res,
  HttpCode,
  HttpStatus,
  SetMetadata,
  Req,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { AdminService } from './admin.service';
import {
  CreateAdminDto,
  UpdateAdminDto,
  CreateLicensePlanDto,
  UpdateLicensePlanDto,
  CreateAppVersionDto,
} from './dto/admin.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';

const Roles = (...roles: string[]) => SetMetadata('roles', roles);
type AuthenticatedRequest = Request & { user: { sub: string } };

@Controller({ path: 'admin', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  // ==================== DASHBOARD ====================

  @Get('dashboard')
  @Roles('super')
  async getDashboard() {
    return this.adminService.getDashboard();
  }

  // ==================== ADMIN USERS ====================

  @Post('admins')
  @Roles('super')
  @HttpCode(HttpStatus.CREATED)
  async createAdmin(
    @Body() dto: CreateAdminDto,
    @Req() req: AuthenticatedRequest,
    @Res() res: Response,
  ) {
    const admin = await this.adminService.createAdmin(dto, req.user.sub);
    return res.status(HttpStatus.CREATED).json(admin);
  }

  @Get('admins')
  @Roles('super')
  async getAdmins() {
    return this.adminService.getAdmins();
  }

  @Patch('admins/:id/toggle')
  @Roles('super')
  async toggleAdmin(@Param('id') id: string, @Req() req: AuthenticatedRequest) {
    return this.adminService.toggleAdmin(id, req.user.sub);
  }

  @Patch('admins/:id')
  @Roles('super')
  async updateAdmin(
    @Param('id') id: string,
    @Body() dto: UpdateAdminDto,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.adminService.updateAdmin(id, dto, req.user.sub);
  }

  @Delete('admins/:id')
  @Roles('super')
  async deleteAdmin(@Param('id') id: string, @Req() req: AuthenticatedRequest) {
    return this.adminService.deleteAdmin(id, req.user.sub);
  }

  // ==================== LICENSE PLANS ====================

  @Post('plans')
  @Roles('super')
  @HttpCode(HttpStatus.CREATED)
  async createPlan(
    @Body() dto: CreateLicensePlanDto,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.adminService.createPlan(dto, req.user.sub);
  }

  @Get('plans')
  @Roles('super')
  async getPlans() {
    return this.adminService.getPlans();
  }

  @Patch('plans/:id')
  @Roles('super')
  async updatePlan(
    @Param('id') id: string,
    @Body() dto: UpdateLicensePlanDto,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.adminService.updatePlan(id, dto, req.user.sub);
  }

  @Delete('plans/:id')
  @Roles('super')
  async deletePlan(@Param('id') id: string, @Req() req: AuthenticatedRequest) {
    return this.adminService.deletePlan(id, req.user.sub);
  }

  // ==================== APP VERSIONS ====================

  @Post('versions')
  @Roles('super')
  @HttpCode(HttpStatus.CREATED)
  async createVersion(
    @Body() dto: CreateAppVersionDto,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.adminService.createVersion(dto, req.user.sub);
  }

  @Get('versions')
  @Roles('super')
  async getVersions(@Query('platform') platform?: string) {
    return this.adminService.getVersions(platform);
  }

  @Get('versions/latest/:platform')
  @Roles('super')
  async getLatestVersion(@Param('platform') platform: string) {
    return this.adminService.getLatestVersion(platform);
  }

  // ==================== USERS ====================

  @Get('users')
  @Roles('super')
  async getUsers(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.adminService.getUsers(
      page ? Number.parseInt(page, 10) : 1,
      limit ? Number.parseInt(limit, 10) : 20,
    );
  }

  @Post('users/:id/suspend')
  @Roles('super')
  @HttpCode(HttpStatus.OK)
  async suspendUser(@Param('id') id: string, @Req() req: AuthenticatedRequest) {
    return this.adminService.suspendUser(id, req.user.sub);
  }

  @Delete('users/:id')
  @Roles('super')
  async deleteUser(@Param('id') id: string, @Req() req: AuthenticatedRequest) {
    return this.adminService.deleteUser(id, req.user.sub);
  }

  // ==================== FEATURE FLAGS ====================

  @Get('features')
  @Roles('super')
  async getFeatureFlags() {
    return this.adminService.getFeatureFlags();
  }

  @Patch('features/:id/toggle')
  @Roles('super')
  async toggleFeatureFlag(
    @Param('id') id: string,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.adminService.toggleFeatureFlag(id, req.user.sub);
  }

  // ==================== EXPORT REPORTS ====================

  @Get('export/users')
  @Roles('super')
  async exportUsersCsv(@Res() res: Response) {
    const csv = await this.adminService.exportUsersCsv();
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=users.csv');
    return res.send(csv);
  }

  @Get('export/licenses')
  @Roles('super')
  async exportLicensesCsv(@Res() res: Response) {
    const csv = await this.adminService.exportLicensesCsv();
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename=licenses.csv');
    return res.send(csv);
  }

  @Get('export/activations')
  @Roles('super')
  async exportActivationsCsv(@Res() res: Response) {
    const csv = await this.adminService.exportActivationsCsv();
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader(
      'Content-Disposition',
      'attachment; filename=activations.csv',
    );
    return res.send(csv);
  }
}
