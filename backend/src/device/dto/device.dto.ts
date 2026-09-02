import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';

const platforms = ['android', 'ios', 'windows', 'macos', 'linux'] as const;

export class RegisterDeviceDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  hardwareFingerprint: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceId: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name: string;

  @IsIn(platforms)
  platform: string;

  @IsString()
  @IsOptional()
  @MaxLength(64)
  ip?: string;
}

export class BanDeviceDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceId: string;

  @IsString()
  @MinLength(3)
  @MaxLength(500)
  reason: string;

  @IsString()
  @IsOptional()
  @MaxLength(120)
  bannedBy?: string;
}

export class UpdateDeviceDto {
  @IsString()
  @IsOptional()
  @MinLength(1)
  @MaxLength(120)
  name?: string;

  @IsBoolean()
  @IsOptional()
  isActive?: boolean;
}
