import { createContext, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import api from '../../lib/api';
import type { User, LoginCredentials, LoginResponse, MeResponse } from './types';

interface AuthContextType {
  user: User | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let active = true;

    async function loadUser() {
      const token = localStorage.getItem('admin_token');
      if (!token) {
        if (active) setIsLoading(false);
        return;
      }
      try {
        const response = await api.get<MeResponse>('/admin/auth/me');
        if (active) setUser(response.data.data);
      } catch {
        localStorage.removeItem('admin_token');
        if (active) setUser(null);
      } finally {
        if (active) setIsLoading(false);
      }
    }

    void loadUser();
    return () => { active = false; };
  }, []);

  const login = async (credentials: LoginCredentials) => {
    const response = await api.post<LoginResponse>('/admin/auth/login', credentials);
    const { token, user: userData } = response.data.data;
    localStorage.setItem('admin_token', token);
    setUser(userData);
  };

  const logout = async () => {
    try {
      await api.post('/admin/auth/logout');
    } finally {
      localStorage.removeItem('admin_token');
      setUser(null);
    }
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        isLoading,
        isAuthenticated: !!user,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components -- standard context pattern
export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
