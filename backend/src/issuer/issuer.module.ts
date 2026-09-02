import { Module } from '@nestjs/common';
import { AuditModule } from '../audit/audit.module';
import { AuthModule } from '../auth/auth.module';
import { IssuerController } from './issuer.controller';
import { IssuerService } from './issuer.service';

@Module({
  imports: [AuthModule, AuditModule],
  controllers: [IssuerController],
  providers: [IssuerService],
})
export class IssuerModule {}
