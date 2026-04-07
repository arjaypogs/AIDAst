/**
 * Authentication Context
 * Manages JWT auth state, login, password change, and logout.
 */
import { createContext, useContext, useState, useEffect, useCallback } from 'react';
import {
  getStoredToken, getStoredUser, clearAuth, storeUser,
  login as apiLogin, fetchMe,
} from '../services/authService';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(getStoredUser);
  const [token, setToken] = useState(getStoredToken);
  const [loading, setLoading] = useState(true);
  const [backendUnreachable, setBackendUnreachable] = useState(false);

  // On mount: if we have a token, validate it by fetching /auth/me.
  // We never assume "no auth required" — auth is always required now.
  useEffect(() => {
    let cancelled = false;

    if (!token) {
      setLoading(false);
      return;
    }

    fetchMe()
      .then((freshUser) => {
        if (cancelled) return;
        setUser(freshUser);
        storeUser(freshUser);
        setBackendUnreachable(false);
      })
      .catch((err) => {
        if (cancelled) return;
        // 401 → clear stale token and let the user re-login.
        if (err?.response?.status === 401) {
          clearAuth();
          setToken(null);
          setUser(null);
        } else {
          // Network/5xx → don't bypass auth, surface the error instead.
          setBackendUnreachable(true);
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => { cancelled = true; };
  }, [token]);

  const login = useCallback(async (username, password) => {
    const result = await apiLogin(username, password);
    setToken(result.token);
    setUser(result.user);
    setBackendUnreachable(false);
    return result;
  }, []);

  const logout = useCallback(() => {
    clearAuth();
    setToken(null);
    setUser(null);
  }, []);

  const refreshUser = useCallback((freshUser) => {
    setUser(freshUser);
    storeUser(freshUser);
  }, []);

  const isAuthenticated = !!token && !!user;
  const mustChangePassword = !!user?.must_change_password;

  return (
    <AuthContext.Provider value={{
      user, token, loading,
      isAuthenticated,
      mustChangePassword,
      backendUnreachable,
      login, logout, refreshUser,
    }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
