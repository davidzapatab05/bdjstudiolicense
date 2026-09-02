import {
  Controller,
  Post,
  Get,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
  SetMetadata,
  Req,
} from '@nestjs/common';
import type { Request } from 'express';
import { LicenseService } from './license.service';
import {
  ActivateLicenseDto,
  ValidateLicenseDto,
  RevokeLicenseDto,
  CreateLicenseDto,
  GenerateBatchDto,
} from './dto/license.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';

const Roles = (...roles: string[]) => SetMetadata('roles', roles);

@Controller({ path: 'licenses', version: '1' })
export class LicenseController {
  constructor(private readonly licenseService: LicenseService) {}

  // Public endpoints (no auth required)
  @Post('activate')
  @HttpCode(HttpStatus.OK)
  async activate(@Body() dto: ActivateLicenseDto, @Req() req: Request) {
    return this.licenseService.activate(dto, req.socket.remoteAddress);
  }

  @Post('validate')
  @HttpCode(HttpStatus.OK)
  async validate(@Body() dto: ValidateLicenseDto) {
    return this.licenseService.validate(dto);
  }

  // Admin-only endpoints
  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  @HttpCode(HttpStatus.CREATED)
  async create(@Body() dto: CreateLicenseDto) {
    return this.licenseService.create(dto);
  }

  @Post('generate-batch')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  @HttpCode(HttpStatus.CREATED)
  async generateBatch(@Body() dto: GenerateBatchDto) {
    return this.licenseService.generateBatch(dto);
  }

  @Get()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  async getAll(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.licenseService.getAll(
      page ? Number.parseInt(page, 10) : 1,
      limit ? Number.parseInt(limit, 10) : 20,
    );
  }

  @Get(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  async getById(@Param('id') id: string) {
    return this.licenseService.getById(id);
  }

  @Get(':licenseKey/activations')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  async getActivations(@Param('licenseKey') licenseKey: string) {
    return this.licenseService.getActivations(licenseKey);
  }

  @Post(':licenseKey/revoke')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  @HttpCode(HttpStatus.OK)
  async revoke(
    @Param('licenseKey') licenseKey: string,
    @Body() dto: RevokeLicenseDto,
  ) {
    return this.licenseService.revoke({ ...dto, licenseKey });
  }
}
