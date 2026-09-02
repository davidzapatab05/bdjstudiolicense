import {
  IsString,
  IsOptional,
  IsNumber,
  IsBoolean,
  IsEnum,
  IsEmail,
  MinLength,
} from 'class-validator';

export class CreateAdminDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(12)
  password: string;

  @IsString()
  name: string;
}

export class UpdateAdminDto {
  @IsEmail()
  @IsOptional()
  email?: string;

  @IsString()
  @IsOptional()
  @MinLength(12)
  password?: string;

  @IsString()
  @IsOptional()
  name?: string;
}

export class CreateLicensePlanDto {
  @IsString()
  name: string;

  @IsEnum(['lifetime', 'monthly', 'annual'])
  type: string;

  @IsNumber()
  price: number;

  @IsNumber()
  @IsOptional()
  maxDevices?: number;

  @IsString()
  @IsOptional()
  features?: string;
}

export class UpdateLicensePlanDto {
  @IsString()
  @IsOptional()
  name?: string;

  @IsNumber()
  @IsOptional()
  price?: number;

  @IsNumber()
  @IsOptional()
  maxDevices?: number;

  @IsBoolean()
  @IsOptional()
  isActive?: boolean;

  @IsString()
  @IsOptional()
  features?: string;
}

export class CreateAppVersionDto {
  @IsString()
  version: string;

  @IsString()
  platform: string;

  @IsString()
  downloadUrl: string;

  @IsBoolean()
  @IsOptional()
  isRequired?: boolean;

  @IsString()
  @IsOptional()
  releaseNotes?: string;
}
