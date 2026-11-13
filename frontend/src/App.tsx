import { Navigate, Route, Routes } from 'react-router-dom'
import { ProtectedRoute } from './features/auth/components/ProtectedRoute'
import { AdminLayout } from './features/admin/components/AdminLayout'
import HomePage from './pages/HomePage'
import LoginPage from './pages/LoginPage'
import AdminHomePage from './pages/AdminHomePage'
import UsersPage from './pages/UsersPage'
import LivestockPage from './pages/LivestockPage'
import SellerVerificationPage from './pages/SellerVerificationPage'
import TransactionsPage from './pages/TransactionsPage'
import ActivitiesPage from './pages/ActivitiesPage'
import ReportsPage from './pages/ReportsPage'
import SettingsPage from './pages/SettingsPage'
import './features/admin/components/AdminVisualSystem.css'

export default function App() {
  return (
    <Routes>
      {/* Public: the product home page. The admin console starts at /dashboard. */}
      <Route path="/" element={<HomePage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AdminLayout />}>
          <Route path="/dashboard" element={<AdminHomePage />} />
          <Route path="/users" element={<UsersPage />} />
          <Route path="/livestock" element={<LivestockPage />} />
          <Route path="/seller-verification" element={<SellerVerificationPage />} />
          <Route path="/transactions" element={<TransactionsPage />} />
          <Route path="/activities" element={<ActivitiesPage />} />
          <Route path="/reports" element={<ReportsPage />} />
          <Route path="/settings" element={<SettingsPage />} />
          <Route path="/admin/settings" element={<Navigate to="/settings" replace />} />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
