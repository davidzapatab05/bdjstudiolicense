import { Type } from 'class-transformer';
import {
  IsDate,
  IsEmail,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

const products = [
  'bdj_studio_sample_pad',
  'bdj_studio_synth_pro',
  'bdj_studio_stems_music',
  'bdj_studio_wave_video',
  'bdj_studio_voice_spot',
  'bdj_studio_search_pro',
] as const;
const statuses = ['active', 'superseded', 'revoked'] as const;

export class SyncCustomerDto {
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  externalId: string;

  @IsString()
  @MinLength(1)
  @MaxLength(120)
  name: string;

  @IsEmail()
  @MaxLength(254)
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceId: string;
}

export class SyncOfflineLicenseDto {
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  externalId: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  customerExternalId: string;

  @IsIn(products)
  product: string;

  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceId: string;

  @IsString()
  @MinLength(1)
  @MaxLength(64)
  plan: string;

  @Matches(/^[a-f0-9]{64}$/)
  tokenDigest: string;

  @Type(() => Date)
  @IsDate()
  issuedAt: Date;

  @Type(() => Date)
  @IsDate()
  @IsOptional()
  expiresAt?: Date;

  @IsIn(statuses)
  @IsOptional()
  status?: string;
}

export class SyncOfflineDeviceBlockDto {
  @IsString()
  @MinLength(8)
  @MaxLength(256)
  deviceId: string;

  @IsString()
  @MinLength(3)
  @MaxLength(500)
  reason: string;

  @Type(() => Date)
  @IsDate()
  blockedAt: Date;
}
