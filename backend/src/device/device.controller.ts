import {
  Controller,
  Post,
  Get,
  Patch,
  Body,
  Param,
  Query,
  UseGuards,
  HttpCode,
  HttpStatus,
  SetMetadata,
} from '@nestjs/common';
import { DeviceService } from './device.service';
import {
  RegisterDeviceDto,
  BanDeviceDto,
  UpdateDeviceDto,
} from './dto/device.dto';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';

const Roles = (...roles: string[]) => SetMetadata('roles', roles);

@Controller({ path: 'devices', version: '1' })
export class DeviceController {
  constructor(private readonly deviceService: DeviceService) {}

  // Public endpoint (app registers device during activation)
  @Post('register')
  @HttpCode(HttpStatus.CREATED)
  async register(@Body() dto: RegisterDeviceDto) {
    return this.deviceService.register(dto);
  }

  // Admin-only endpoints
  @Get()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  async getAll(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.deviceService.getAll(
      page ? Number.parseInt(page, 10) : 1,
      limit ? Number.parseInt(limit, 10) : 20,
    );
  }

  @Get(':deviceId')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  async getById(@Param('deviceId') deviceId: string) {
    return this.deviceService.getById(deviceId);
  }

  @Patch(':deviceId')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  async update(
    @Param('deviceId') deviceId: string,
    @Body() dto: UpdateDeviceDto,
  ) {
    return this.deviceService.update(deviceId, dto);
  }

  @Post('ban')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  @HttpCode(HttpStatus.OK)
  async ban(@Body() dto: BanDeviceDto) {
    return this.deviceService.ban(dto);
  }

  @Post(':deviceId/unban')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('super')
  @HttpCode(HttpStatus.OK)
  async unban(@Param('deviceId') deviceId: string) {
    return this.deviceService.unban(deviceId);
  }
}
