FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache postgresql-client
COPY backend/package.json ./backend/
WORKDIR /app/backend
RUN npm install --omit=dev
COPY backend/src ./src
COPY frontend ../frontend
COPY database ../database
EXPOSE 4000
CMD ["node", "src/server.js"]
