import { Navigate, Route, Routes } from 'react-router-dom'
import { ProtectedRoute } from './features/auth/components/ProtectedRoute'
import { AdminLayout } from './features/admin/components/AdminLayout'
import LoginPage from './pages/LoginPage'
import AdminHomePage from './pages/AdminHomePage'
import UsersPage from './pages/UsersPage'
import LivestockPage from './pages/LivestockPage'
import SellerVerificationPage from './pages/SellerVerificationPage'
import TransactionsPage from './pages/TransactionsPage'
import ActivitiesPage from './pages/ActivitiesPage'
import ReportsPage from './pages/ReportsPage'
import SettingsPage from './pages/SettingsPage'

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route element={<ProtectedRoute />}>
        <Route element={<AdminLayout />}>
          <Route path="/" element={<AdminHomePage />} />
          <Route path="/users" element={<UsersPage />} />
          <Route path="/livestock" element={<LivestockPage />} />
          <Route path="/seller-verification" element={<SellerVerificationPage />} />
          <Route path="/transactions" element={<TransactionsPage />} />
          <Route path="/activities" element={<ActivitiesPage />} />
          <Route path="/reports" element={<ReportsPage />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}