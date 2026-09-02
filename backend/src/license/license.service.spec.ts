import { Test, TestingModule } from '@nestjs/testing';
import { HttpException, HttpStatus } from '@nestjs/common';
import { LicenseService } from './license.service';
import { PrismaService } from '../prisma/prisma.service';
import {
  ActivateLicenseDto,
  ValidateLicenseDto,
  RevokeLicenseDto,
  GenerateBatchDto,
} from './dto/license.dto';

/**
 * Fase 11.1 - Tests de licenciamiento (backend).
 * PrismaService se mockea completo: los tests son unitarios y NO tocan la BD.
 */
describe('LicenseService', () => {
  let service: LicenseService;
  let prisma: {
    license: Record<string, jest.Mock>;
    device: Record<string, jest.Mock>;
    activation: Record<string, jest.Mock>;
    bannedDevice: Record<string, jest.Mock>;
    $transaction: jest.Mock;
  };

  beforeEach(async () => {
    prisma = {
      license: {
        findUnique: jest.fn(),
        update: jest.fn(),
        create: jest.fn(),
        findMany: jest.fn(),
        count: jest.fn(),
      },
      device: {
        create: jest.fn(),
        update: jest.fn(),
        updateMany: jest.fn(),
      },
      activation: {
        create: jest.fn(),
      },
      bannedDevice: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
      // Prisma recibe promesas ya construidas y las ejecuta atómicamente. El
      // mock debe conservar ese contrato para que el test cubra el flujo real.
      $transaction: jest.fn(async (operations: Array<Promise<unknown>>) =>
        Promise.all(operations),
      ),
    };

    const module: TestingModule = await Test.createTestingModule({
      providers: [LicenseService, { provide: PrismaService, useValue: prisma }],
    }).compile();

    service = module.get<LicenseService>(LicenseService);
  });

  const baseDto: ActivateLicenseDto = {
    licenseKey: 'SPP-AAAA-BBBB-CCCC',
    hardwareFingerprint: 'fp-123',
    deviceId: 'dev-1',
    platform: 'android',
  };

  describe('activate', () => {
    it('lanza NOT_FOUND si la licencia no existe', async () => {
      prisma.license.findUnique.mockResolvedValue(null);
      await expect(service.activate(baseDto)).rejects.toMatchObject({
        status: HttpStatus.NOT_FOUND,
      });
    });

    it('lanza FORBIDDEN si la licencia está revocada', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        status: 'revoked',
        devices: [],
      });
      await expect(service.activate(baseDto)).rejects.toBeInstanceOf(
        HttpException,
      );
    });

    it('lanza FORBIDDEN si la licencia expiró', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        status: 'active',
        expiresAt: new Date(Date.now() - 1000),
        devices: [],
      });
      await expect(service.activate(baseDto)).rejects.toMatchObject({
        status: HttpStatus.FORBIDDEN,
      });
    });

    it('rechaza la activación de un dispositivo bloqueado', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        licenseKey: baseDto.licenseKey,
        status: 'active',
        maxDevices: 3,
        userId: 'u1',
        devices: [],
      });
      prisma.bannedDevice.findFirst.mockResolvedValue({
        id: 'blocked-1',
        deviceId: baseDto.deviceId,
      });

      await expect(service.activate(baseDto)).rejects.toMatchObject({
        status: HttpStatus.FORBIDDEN,
      });
      expect(prisma.device.create).not.toHaveBeenCalled();
      expect(prisma.device.update).not.toHaveBeenCalled();
      expect(prisma.activation.create).not.toHaveBeenCalled();
    });

    it('rechaza cuando se alcanza el máximo de dispositivos', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        status: 'active',
        maxDevices: 1,
        userId: 'u1',
        devices: [{ id: 'd1', isActive: true, hardwareFingerprint: 'otro-fp' }],
      });
      await expect(service.activate(baseDto)).rejects.toMatchObject({
        status: HttpStatus.FORBIDDEN,
      });
    });

    it('reutiliza el dispositivo existente (mismo fingerprint) sin crear uno nuevo', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        licenseKey: baseDto.licenseKey,
        status: 'active',
        maxDevices: 3,
        userId: 'u1',
        offlineDays: 30,
        devices: [{ id: 'd1', isActive: true, hardwareFingerprint: 'fp-123' }],
      });
      prisma.device.update.mockResolvedValue({
        deviceId: 'dev-1',
        name: 'Device-android',
      });
      prisma.activation.create.mockResolvedValue({});

      const res = await service.activate(baseDto);

      expect(prisma.device.update).toHaveBeenCalled();
      expect(prisma.device.create).not.toHaveBeenCalled();
      expect(prisma.activation.create).toHaveBeenCalled();
      expect(res.success).toBe(true);
      expect(res.status).toBe('active');
    });

    it('crea un dispositivo nuevo y activa una licencia inactive', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        licenseKey: baseDto.licenseKey,
        status: 'inactive',
        maxDevices: 3,
        userId: null,
        offlineDays: 30,
        devices: [],
      });
      prisma.device.create.mockResolvedValue({
        deviceId: 'dev-1',
        name: 'Device-android',
      });
      prisma.activation.create.mockResolvedValue({});
      prisma.license.update.mockResolvedValue({});

      const res = await service.activate(baseDto);

      expect(prisma.device.create).toHaveBeenCalled();
      // La licencia inactive debe pasar a active.
      const activeDataMatcher: unknown = expect.objectContaining({
        status: 'active',
      });
      expect(prisma.license.update).toHaveBeenCalledWith(
        expect.objectContaining({ data: activeDataMatcher }),
      );
      expect(res.success).toBe(true);
    });
  });

  describe('validate', () => {
    it('rechaza si el dispositivo no está autorizado', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        status: 'active',
        devices: [],
      });
      const dto: ValidateLicenseDto = {
        licenseKey: baseDto.licenseKey,
        hardwareFingerprint: 'fp-desconocido',
      };
      await expect(service.validate(dto)).rejects.toMatchObject({
        status: HttpStatus.FORBIDDEN,
      });
    });

    it('valida una licencia con dispositivo activo', async () => {
      prisma.license.findUnique.mockResolvedValue({
        id: 'l1',
        licenseKey: baseDto.licenseKey,
        status: 'active',
        offlineDays: 30,
        plan: { name: 'Pro' },
        devices: [{ hardwareFingerprint: 'fp-123', isActive: true }],
      });
      const okDto: ValidateLicenseDto = {
        licenseKey: baseDto.licenseKey,
        hardwareFingerprint: 'fp-123',
      };
      const res = await service.validate(okDto);
      expect(res.valid).toBe(true);
      expect(res.plan).toBe('Pro');
    });
  });

  describe('revoke', () => {
    it('marca la licencia revoked y desactiva sus dispositivos', async () => {
      prisma.license.findUnique.mockResolvedValue({ id: 'l1' });
      prisma.license.update.mockResolvedValue({});
      prisma.device.updateMany.mockResolvedValue({});

      const revokeDto: RevokeLicenseDto = { licenseKey: baseDto.licenseKey };
      const res = await service.revoke(revokeDto);

      expect(prisma.license.update).toHaveBeenCalledWith(
        expect.objectContaining({
          data: { status: 'revoked' },
        }),
      );
      expect(prisma.device.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({ data: { isActive: false } }),
      );
      expect(res.success).toBe(true);
    });
  });

  describe('generateBatch', () => {
    it('genera N licencias con formato SPP-XXXX-XXXX-XXXX', async () => {
      const created: Array<{ id: string; licenseKey: string; status: string }> =
        [];
      prisma.license.create.mockImplementation(
        (args: { data: { licenseKey: string; status: string } }) => {
          const l = { id: `id-${created.length}`, ...args.data };
          created.push(l);
          return Promise.resolve(l);
        },
      );

      const batchDto: GenerateBatchDto = { count: 5 };
      const res = await service.generateBatch(batchDto);

      expect(res.count).toBe(5);
      expect(prisma.license.create).toHaveBeenCalledTimes(5);
      expect(prisma.$transaction).toHaveBeenCalledTimes(1);
      for (const l of res.licenses) {
        expect(l.licenseKey).toMatch(
          /^SPP-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}$/,
        );
        expect(l.status).toBe('inactive');
      }
    });

    it('las claves generadas son únicas', async () => {
      prisma.license.create.mockImplementation(
        (args: { data: { licenseKey: string } }) =>
          Promise.resolve({ id: args.data.licenseKey, ...args.data }),
      );
      const batchDto2: GenerateBatchDto = { count: 50 };
      const res = await service.generateBatch(batchDto2);
      const keys = res.licenses.map((l) => l.licenseKey);
      expect(new Set(keys).size).toBe(keys.length);
    });
  });
});
