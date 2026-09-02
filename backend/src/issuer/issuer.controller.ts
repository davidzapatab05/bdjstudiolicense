import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Req,
  SetMetadata,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import {
  SyncCustomerDto,
  SyncOfflineDeviceBlockDto,
  SyncOfflineLicenseDto,
} from './dto/issuer.dto';
import { IssuerService } from './issuer.service';

const Roles = (...roles: string[]) => SetMetadata('roles', roles);
type AuthenticatedRequest = Request & { user: { sub: string } };

@Controller({ path: 'issuer', version: '1' })
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('super')
export class IssuerController {
  constructor(private readonly issuer: IssuerService) {}

  @Post('customers/sync')
  syncCustomer(@Body() dto: SyncCustomerDto, @Req() req: AuthenticatedRequest) {
    return this.issuer.syncCustomer(dto, req.user.sub);
  }

  @Post('licenses/sync')
  syncLicense(
    @Body() dto: SyncOfflineLicenseDto,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.issuer.syncLicense(dto, req.user.sub);
  }

  @Post('device-blocks/sync')
  syncDeviceBlock(
    @Body() dto: SyncOfflineDeviceBlockDto,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.issuer.syncDeviceBlock(dto, req.user.sub);
  }

  @Delete('device-blocks/:deviceId')
  removeDeviceBlock(
    @Param('deviceId') deviceId: string,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.issuer.removeDeviceBlock(deviceId, req.user.sub);
  }

  @Delete('customers/:externalId')
  removeCustomer(
    @Param('externalId') externalId: string,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.issuer.removeCustomer(externalId, req.user.sub);
  }

  @Delete('licenses/:externalId')
  removeLicense(
    @Param('externalId') externalId: string,
    @Req() req: AuthenticatedRequest,
  ) {
    return this.issuer.removeLicense(externalId, req.user.sub);
  }

  @Get('snapshot')
  snapshot() {
    return this.issuer.snapshot();
  }
}
