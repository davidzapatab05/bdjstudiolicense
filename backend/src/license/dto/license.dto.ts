import {
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import { Type } from 'class-transformer';

const platforms = ['android', 'ios', 'windows', 'macos', 'linux'] as const;

export class ActivateLicenseDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  licenseKey: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  hardwareFingerprint: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceId: string;

  @IsIn(platforms)
  platform: string;

  @IsString()
  @IsOptional()
  @MaxLength(120)
  deviceName?: string;
}

export class ValidateLicenseDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  licenseKey: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  hardwareFingerprint: string;
}

export class RevokeLicenseDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  licenseKey: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  reason?: string;
}

export class CreateLicenseDto {
  @IsUUID()
  @IsOptional()
  userId?: string;

  @IsUUID()
  @IsOptional()
  planId?: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10)
  @IsOptional()
  maxDevices?: number;

  @IsIn(['perpetual', 'monthly', 'annual'])
  @IsOptional()
  type?: string;
}

export class GenerateBatchDto {
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  count: number;

  @IsUUID()
  @IsOptional()
  planId?: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10)
  @IsOptional()
  maxDevices?: number;
}
