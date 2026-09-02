import {
  Injectable,
  HttpException,
  HttpStatus,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';
import { RegisterDto, LoginDto, RefreshTokenDto } from './dto/auth.dto';
import { jwtRefreshSecret } from '../config/secrets';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

interface JwtPayload {
  sub: string;
  email: string;
  role: string;
}

@Injectable()
export class AuthService {
  private readonly SALT_ROUNDS = 12;
  private readonly ACCESS_TOKEN_EXPIRY = '15m';
  private readonly REFRESH_TOKEN_EXPIRY = '30d';

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
  ) {}

  async register(dto: RegisterDto): Promise<TokenPair> {
    const email = dto.email.trim().toLowerCase();
    const existing = await this.prisma.user.findUnique({
      where: { email },
    });

    if (existing) {
      throw new HttpException('Email already registered', HttpStatus.CONFLICT);
    }

    const hashedPassword = await bcrypt.hash(dto.password, this.SALT_ROUNDS);

    const user = await this.prisma.user.create({
      data: {
        email,
        password: hashedPassword,
        name: dto.name ?? email.split('@')[0],
        displayName: dto.displayName ?? dto.name,
        role: 'user',
        isVerified: false,
      },
    });

    return this.generateTokenPair(user.id, user.email, user.role);
  }

  async login(dto: LoginDto): Promise<TokenPair> {
    const email = dto.email.trim().toLowerCase();
    const user = await this.prisma.user.findUnique({
      where: { email },
    });

    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const isPasswordValid = await bcrypt.compare(dto.password, user.password);

    if (!isPasswordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    return this.generateTokenPair(user.id, user.email, user.role);
  }

  async adminLogin(email: string, password: string): Promise<TokenPair> {
    const normalizedEmail = email.trim().toLowerCase();
    const admin = await this.prisma.adminUser.findUnique({
      where: { email: normalizedEmail },
    });

    if (!admin?.isActive) {
      throw new UnauthorizedException('Invalid credentials');
    }

    const isPasswordValid = await bcrypt.compare(password, admin.password);

    if (!isPasswordValid) {
      throw new UnauthorizedException('Invalid credentials');
    }

    return this.generateTokenPair(admin.id, admin.email, admin.role);
  }

  async refreshToken(dto: RefreshTokenDto): Promise<TokenPair> {
    try {
      const payload = this.jwtService.verify<JwtPayload>(dto.refreshToken, {
        secret: jwtRefreshSecret,
      });

      if (payload.role === 'user') {
        const user = await this.prisma.user.findUnique({
          where: { id: payload.sub },
        });
        if (!user) throw new UnauthorizedException('User not found');
        return this.generateTokenPair(user.id, user.email, user.role);
      }
      const admin = await this.prisma.adminUser.findUnique({
        where: { id: payload.sub },
      });
      if (!admin?.isActive || admin.role !== payload.role) {
        throw new UnauthorizedException('Admin not found');
      }
      return this.generateTokenPair(admin.id, admin.email, admin.role);
    } catch {
      throw new UnauthorizedException('Invalid refresh token');
    }
  }

  async validateToken(token: string): Promise<boolean> {
    try {
      await this.jwtService.verifyAsync(token);
      return true;
    } catch {
      return false;
    }
  }

  async getProfile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        displayName: true,
        role: true,
        isVerified: true,
        createdAt: true,
      },
    });

    if (user) return user;

    const admin = await this.prisma.adminUser.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        isActive: true,
        createdAt: true,
      },
    });
    if (!admin?.isActive || admin.role !== 'super') {
      throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    }

    return admin;
  }

  private generateTokenPair(
    userId: string,
    email: string,
    role: string,
  ): TokenPair {
    const payload: JwtPayload = { sub: userId, email, role };

    const accessToken = this.jwtService.sign(payload, {
      expiresIn: this.ACCESS_TOKEN_EXPIRY,
    });

    const refreshToken = this.jwtService.sign(payload, {
      secret: jwtRefreshSecret,
      expiresIn: this.REFRESH_TOKEN_EXPIRY,
    });

    return { accessToken, refreshToken };
  }
}
