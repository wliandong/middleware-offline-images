const appDatabase = process.env.MONGODB_DATABASE || 'appdb';
const appUser = process.env.MONGODB_USER;
const appPassword = process.env.MONGODB_PASSWORD;

if (!appUser || !appPassword) {
  throw new Error('MONGODB_USER and MONGODB_PASSWORD are required');
}

db.getSiblingDB(appDatabase).createUser({
  user: appUser,
  pwd: appPassword,
  roles: [{ role: 'readWrite', db: appDatabase }],
});
