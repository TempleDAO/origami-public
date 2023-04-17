# Build Stage 1
FROM node:18-alpine AS appbuild
WORKDIR /app
COPY package.json yarn.lock tsconfig.json ./
COPY abi/ abi/
RUN yarn install
COPY ./src ./src
RUN yarn build

# Build Stage 2 (ie runtime, without dev dependencies)
FROM node:18-alpine
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --production
COPY --from=appbuild /app/dist ./dist
CMD ["node", "dist/main.js"]
