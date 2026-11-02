import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// ponytail: dev proxy to Rails instead of rack-cors
const rails = 'http://localhost:3000'
export default defineConfig({
  plugins: [react()],
  server: { proxy: { '/customer': rails, '/pickups': rails, '/devices': rails } },
})
