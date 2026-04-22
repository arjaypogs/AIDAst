/**
 * Axios API client configuration
 */
import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000/api';

const apiClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 120000, // 2 minutes for long commands
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor - attach JWT token
apiClient.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('aso_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response interceptor — handle 401 (expired/invalid token).
// We must NEVER call window.location.reload() here: a reload would re-mount
// every context, which would re-fire the same protected requests, which would
// 401 again, which would reload again — an infinite loop. Instead we clear the
// stored auth and emit an event so AuthContext can transition to <Login />
// without unmounting the React tree.
apiClient.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      const url = error.config?.url || '';
      const isAuthEndpoint = url.includes('/auth/');
      if (!isAuthEndpoint && localStorage.getItem('aso_token')) {
        localStorage.removeItem('aso_token');
        localStorage.removeItem('aso_user');
        window.dispatchEvent(new CustomEvent('aso:auth-cleared'));
      }
    }
    const message = error.response?.data?.detail || error.message || 'An error occurred';
    console.error('API Error:', message);
    return Promise.reject(error);
  }
);

export default apiClient;
