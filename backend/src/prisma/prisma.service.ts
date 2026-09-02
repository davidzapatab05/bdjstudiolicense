import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.$connect();
    // Evita que la API arranque con un Prisma Client nuevo sobre una base sin
    // las tablas requeridas. Sin este fail-fast el problema aparece después
    // como P2021 en una solicitud administrativa difícil de diagnosticar.
    const [schema] = await this.$queryRawUnsafe<
      Array<{
        customers: string | null;
        offlineLicenses: string | null;
        offlineDeviceBlocks: string | null;
      }>
    >(
      `SELECT
        to_regclass('public.customers')::text AS "customers",
        to_regclass('public.offline_licenses')::text AS "offlineLicenses",
        to_regclass('public.offline_device_blocks')::text AS "offlineDeviceBlocks"`,
    );
    if (
      !schema?.customers ||
      !schema.offlineLicenses ||
      !schema.offlineDeviceBlocks
    ) {
      throw new Error(
        'Database schema is incomplete. Apply the Prisma migrations before starting the API.',
      );
    }
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
