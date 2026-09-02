import 'dotenv/config';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('Seeding database...');

  // Bootstrap es de un solo uso: nunca se sobrescribe una cuenta existente
  // ni se versiona un hash/credencial administrativa en el repositorio.
  if ((await prisma.adminUser.count()) === 0) {
    const email = process.env.BOOTSTRAP_SUPER_ADMIN_EMAIL?.trim().toLowerCase();
    const password = process.env.BOOTSTRAP_SUPER_ADMIN_PASSWORD;
    const name =
      process.env.BOOTSTRAP_SUPER_ADMIN_NAME?.trim() || 'Super Admin';
    if (!email || !password || password.length < 12) {
      throw new Error(
        'No admin exists. Set BOOTSTRAP_SUPER_ADMIN_EMAIL and BOOTSTRAP_SUPER_ADMIN_PASSWORD (12+ chars) before seeding.',
      );
    }
    const bcrypt = await import('bcrypt');
    await prisma.adminUser.create({
      data: {
        email,
        password: await bcrypt.hash(password, 12),
        name,
        role: 'super',
        isActive: true,
      },
    });
    console.log(`Initial super admin created: ${email}`);
  }

  // Create default license plans
  const plans = [
    {
      name: 'Free Trial',
      type: 'monthly',
      price: 0,
      maxDevices: 1,
      features: JSON.stringify(['basic_pads', '8_sounds', '2_workspaces']),
    },
    {
      name: 'Pro Monthly',
      type: 'monthly',
      price: 9.99,
      maxDevices: 3,
      features: JSON.stringify([
        'unlimited_pads',
        'unlimited_sounds',
        'unlimited_workspaces',
        'midi_support',
        'effects',
        'performance_mode',
      ]),
    },
    {
      name: 'Pro 6-Months',
      type: 'monthly',
      price: 49.99,
      maxDevices: 3,
      features: JSON.stringify([
        'unlimited_pads',
        'unlimited_sounds',
        'unlimited_workspaces',
        'midi_support',
        'effects',
        'performance_mode',
      ]),
    },
    {
      name: 'Pro Annual',
      type: 'annual',
      price: 89.99,
      maxDevices: 3,
      features: JSON.stringify([
        'unlimited_pads',
        'unlimited_sounds',
        'unlimited_workspaces',
        'midi_support',
        'effects',
        'performance_mode',
      ]),
    },
    {
      name: 'Lifetime',
      type: 'lifetime',
      price: 199.99,
      maxDevices: 5,
      features: JSON.stringify([
        'unlimited_pads',
        'unlimited_sounds',
        'unlimited_workspaces',
        'midi_support',
        'effects',
        'performance_mode',
        'priority_support',
      ]),
    },
  ];

  for (const plan of plans) {
    const existing = await prisma.licensePlan.findFirst({
      where: { name: plan.name },
    });

    if (!existing) {
      await prisma.licensePlan.create({ data: plan });
      console.log(`Plan created: ${plan.name}`);
    } else {
      console.log(`Plan already exists: ${plan.name}`);
    }
  }

  console.log('Seeding completed!');
}

main()
  .catch((e) => {
    console.error('Seeding failed:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
