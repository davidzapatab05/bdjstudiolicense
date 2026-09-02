/* eslint-disable @typescript-eslint/no-unsafe-assignment */
import { NotFoundException } from '@nestjs/common';
import { Test, TestingModule } from '@nestjs/testing';
import { AuditService } from '../audit/audit.service';
import { PrismaService } from '../prisma/prisma.service';
import { IssuerService } from './issuer.service';

describe('IssuerService', () => {
  let service: IssuerService;
  const prisma = {
    customer: { upsert: jest.fn(), findUnique: jest.fn(), findMany: jest.fn() },
    offlineLicense: { upsert: jest.fn(), findMany: jest.fn() },
    offlineDeviceBlock: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
      findMany: jest.fn(),
      delete: jest.fn(),
    },
  };
  const audit = { log: jest.fn() };

  beforeEach(async () => {
    jest.clearAllMocks();
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        IssuerService,
        { provide: PrismaService, useValue: prisma },
        { provide: AuditService, useValue: audit },
      ],
    }).compile();
    service = module.get(IssuerService);
  });

  it('sincroniza un cliente de forma idempotente y normaliza su correo', async () => {
    prisma.customer.upsert.mockResolvedValue({
      id: 'db-customer',
      externalId: 'local-customer',
    });
    await service.syncCustomer(
      {
        externalId: 'local-customer',
        name: 'Ana',
        email: ' ANA@EXAMPLE.COM ',
        deviceId: 'device-12345678',
      },
      'admin-1',
    );
    expect(prisma.customer.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { externalId: 'local-customer' },
        create: expect.objectContaining({ email: 'ana@example.com' }),
      }),
    );
    expect(audit.log).toHaveBeenCalledWith(
      expect.objectContaining({ targetType: 'customer' }),
    );
  });

  it('no registra una licencia si su cliente todavía no existe', async () => {
    prisma.customer.findUnique.mockResolvedValue(null);
    await expect(
      service.syncLicense(
        {
          externalId: 'license-123',
          customerExternalId: 'customer-123',
          product: 'synth_pro',
          deviceId: 'device-12345678',
          plan: 'year',
          tokenDigest: 'a'.repeat(64),
          issuedAt: new Date(),
          status: 'active',
        },
        'admin-1',
      ),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.offlineLicense.upsert).not.toHaveBeenCalled();
  });

  it('guarda solamente el digest de la licencia en el registro remoto', async () => {
    prisma.customer.findUnique.mockResolvedValue({ id: 'db-customer' });
    prisma.offlineLicense.upsert.mockResolvedValue({
      id: 'db-license',
      externalId: 'license-123',
      product: 'synth_pro',
      status: 'active',
    });
    await service.syncLicense(
      {
        externalId: 'license-123',
        customerExternalId: 'customer-123',
        product: 'synth_pro',
        deviceId: 'device-12345678',
        plan: 'year',
        tokenDigest: 'b'.repeat(64),
        issuedAt: new Date(),
        status: 'active',
      },
      'admin-1',
    );
    expect(prisma.offlineLicense.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ tokenDigest: 'b'.repeat(64) }),
      }),
    );
  });

  it('crea y elimina bloqueos de dispositivo de forma idempotente', async () => {
    prisma.offlineDeviceBlock.upsert.mockResolvedValue({
      id: 'block-1',
      deviceId: 'device-12345678',
    });
    await service.syncDeviceBlock(
      { deviceId: 'device-12345678', reason: 'Fraude', blockedAt: new Date() },
      'admin-1',
    );
    expect(prisma.offlineDeviceBlock.upsert).toHaveBeenCalled();
    prisma.offlineDeviceBlock.findUnique.mockResolvedValue({ id: 'block-1' });
    await expect(
      service.removeDeviceBlock('device-12345678', 'admin-1'),
    ).resolves.toEqual({ success: true });
    expect(prisma.offlineDeviceBlock.delete).toHaveBeenCalledWith({
      where: { id: 'block-1' },
    });
  });
});
