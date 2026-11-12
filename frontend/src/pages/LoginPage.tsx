import { useState, type FormEvent } from 'react';
import {
  BarChart3,
  Eye,
  EyeOff,
  LockKeyhole,
  LogIn,
  Mail,
  ShieldCheck,
  Store,
  UserRound,
  UsersRound,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../features/auth/AuthProvider';
import './LoginPage.css';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [rememberMe, setRememberMe] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { login } = useAuth();
  const navigate = useNavigate();

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setIsSubmitting(true);

    try {
      await login({ email, password });
      navigate('/', { replace: true });
    } catch (err: unknown) {
      if (err && typeof err === 'object' && 'response' in err) {
        const axiosError = err as { response?: { status?: number; data?: { message?: string } } };
        if (axiosError.response?.status === 401) {
          setError('Invalid email or password.');
        } else if (axiosError.response?.status === 422) {
          setError('Please enter valid credentials.');
        } else {
          setError('An error occurred. Please try again.');
        }
      } else {
        setError('An error occurred. Please try again.');
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <main className="grid min-h-screen bg-[#f7faf7] lg:grid-cols-2">
      <section className="relative isolate flex min-h-[520px] flex-col items-center justify-center overflow-hidden bg-gradient-to-br from-[#174c2c] via-[#0d4029] to-[#092c20] px-5! py-10! text-white sm:min-h-[570px] sm:px-9! lg:min-h-screen lg:px-12! lg:py-14!">
        <div
          aria-hidden="true"
          data-testid="login-hero-background"
          className="pointer-events-none absolute inset-0 bg-cover bg-[position:center_58%] lg:bg-[position:center_52%]"
          style={{ backgroundImage: "url('/images/login-background.webp')" }}
        />
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-0 bg-gradient-to-b from-green-950/10 via-green-950/5 to-green-950/55"
        />

        <div className="relative z-10 mx-auto! flex w-full max-w-2xl flex-col items-center text-center">
          <img
            src="/images/agrobenta-logo.png"
            alt="AgroBenta"
            className="h-auto w-[min(23rem,80vw)] object-contain drop-shadow-[0_16px_28px_rgba(4,35,22,0.35)] mix-blend-screen"
          />

          <p className="mt-5! text-xl font-semibold tracking-wide text-white sm:mt-6! sm:text-2xl">
            Buy. Sell. Grow. Together.
          </p>

          <div className="mt-7! grid w-full max-w-xl grid-cols-3 gap-2 sm:mt-9! sm:gap-4">
            <div className="flex min-h-28 flex-col items-center justify-center gap-2 rounded-2xl border border-white/25 bg-green-950/35 px-2! py-4! shadow-lg backdrop-blur-sm sm:min-h-32 sm:gap-3 sm:px-4!">
              <Store className="h-7 w-7 text-white sm:h-8 sm:w-8" strokeWidth={1.8} aria-hidden="true" />
              <span className="text-xs font-medium leading-tight sm:text-sm">
                Livestock<br />Marketplace
              </span>
            </div>
            <div className="flex min-h-28 flex-col items-center justify-center gap-2 rounded-2xl border border-white/25 bg-green-950/35 px-2! py-4! shadow-lg backdrop-blur-sm sm:min-h-32 sm:gap-3 sm:px-4!">
              <UsersRound className="h-7 w-7 text-white sm:h-8 sm:w-8" strokeWidth={1.8} aria-hidden="true" />
              <span className="text-xs font-medium leading-tight sm:text-sm">
                Farmers &amp; Buyers<br />Connection
              </span>
            </div>
            <div className="flex min-h-28 flex-col items-center justify-center gap-2 rounded-2xl border border-white/25 bg-green-950/35 px-2! py-4! shadow-lg backdrop-blur-sm sm:min-h-32 sm:gap-3 sm:px-4!">
              <BarChart3 className="h-7 w-7 text-white sm:h-8 sm:w-8" strokeWidth={1.8} aria-hidden="true" />
              <span className="text-xs font-medium leading-tight sm:text-sm">
                Secure &amp;<br />Managed Trading
              </span>
            </div>
          </div>
        </div>

        <div aria-hidden="true" className="pointer-events-none absolute -bottom-24 -left-10 h-44 w-[120%] rotate-[-3deg] rounded-[50%_50%_0_0] bg-emerald-500/35" />
        <div aria-hidden="true" className="pointer-events-none absolute -bottom-32 -left-12 h-44 w-[125%] rotate-[2deg] rounded-[50%_50%_0_0] bg-green-800/70" />
      </section>

      <section className="relative flex min-h-[620px] items-center justify-center overflow-hidden bg-[#f7faf7] px-5! py-12! sm:px-8! lg:min-h-screen lg:px-12! lg:py-16!">
        <div aria-hidden="true" className="pointer-events-none absolute -right-28 -top-36 h-80 w-80 rotate-45 rounded-[4rem] bg-lime-200/55" />
        <div aria-hidden="true" className="pointer-events-none absolute -right-16 -top-28 h-64 w-64 rotate-45 rounded-[3.5rem] bg-green-300/30" />
        <div aria-hidden="true" className="pointer-events-none absolute -bottom-36 -left-28 h-80 w-80 rotate-45 rounded-[4rem] bg-green-200/55" />

        <section className="relative z-10 w-full max-w-[39rem] rounded-[2rem] border border-white bg-white/95 px-6! py-8! shadow-[0_24px_70px_rgba(18,55,32,0.12)] sm:px-10! sm:py-10! lg:px-11! lg:py-10!">
          <header className="mb-7! text-center sm:mb-8!">
            <div className="mx-auto! inline-flex items-center gap-2 rounded-full bg-green-100 px-4! py-2! text-sm font-semibold text-green-800">
              <ShieldCheck className="h-4 w-4 text-green-700" aria-hidden="true" />
              <span>Administrator Access</span>
            </div>
            <h1 className="mt-5! text-3xl font-bold tracking-tight text-green-950 sm:text-[2rem]">
              Administrator Login
            </h1>
            <p className="mt-2! text-sm leading-6 text-slate-600 sm:text-base">
              Access the admin console and manage the AgroBenta platform.
            </p>
          </header>

          <form className="space-y-5!" onSubmit={(e) => void handleSubmit(e)}>
            {error && (
              <div className="rounded-xl border border-red-200 bg-red-50 px-4! py-3! text-sm text-red-800" role="alert">
                {error}
              </div>
            )}

            <div>
              <label htmlFor="email" className="mb-2! flex items-center gap-2 text-sm font-semibold text-slate-900">
                <Mail className="h-4 w-4 text-green-800" aria-hidden="true" />
                Email Address
              </label>
              <div className="relative">
                <UserRound className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
                <input
                  id="email"
                  type="email"
                  className="h-[50px] w-full rounded-xl border border-slate-200 bg-white pl-11! pr-4! text-sm text-slate-900 shadow-sm outline-none transition placeholder:text-slate-400 focus:border-green-700 focus:ring-4 focus:ring-green-700/10 disabled:cursor-not-allowed disabled:bg-slate-50"
                  placeholder="Enter your email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  autoComplete="email"
                  disabled={isSubmitting}
                />
              </div>
            </div>

            <div>
              <label htmlFor="password" className="mb-2! flex items-center gap-2 text-sm font-semibold text-slate-900">
                <LockKeyhole className="h-4 w-4 text-green-800" aria-hidden="true" />
                Password
              </label>
              <div className="relative">
                <LockKeyhole className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
                <input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  className="h-[50px] w-full rounded-xl border border-slate-200 bg-white pl-11! pr-12! text-sm text-slate-900 shadow-sm outline-none transition placeholder:text-slate-400 focus:border-green-700 focus:ring-4 focus:ring-green-700/10 disabled:cursor-not-allowed disabled:bg-slate-50"
                  placeholder="Enter your password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  autoComplete="current-password"
                  disabled={isSubmitting}
                />
                <button
                  type="button"
                  className="absolute right-3 top-1/2 inline-flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-lg text-slate-500 transition hover:bg-slate-100 hover:text-slate-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-green-700"
                  aria-label={showPassword ? 'Hide password' : 'Show password'}
                  aria-pressed={showPassword}
                  onClick={() => setShowPassword((visible) => !visible)}
                  disabled={isSubmitting}
                >
                  {showPassword
                    ? <EyeOff className="h-4 w-4" aria-hidden="true" />
                    : <Eye className="h-4 w-4" aria-hidden="true" />}
                </button>
              </div>
            </div>

            <div className="flex items-center justify-between gap-4 pt-1!">
              <label className="inline-flex cursor-pointer items-center gap-2.5 text-sm text-slate-800">
                <input
                  type="checkbox"
                  className="h-4 w-4 rounded border-slate-300 accent-green-700 focus:ring-green-700"
                  checked={rememberMe}
                  onChange={(e) => setRememberMe(e.target.checked)}
                  disabled={isSubmitting}
                />
                <span>Remember me</span>
              </label>
            </div>

            <button
              type="submit"
              className="mt-2! inline-flex h-[58px] w-full items-center justify-center gap-3 rounded-2xl bg-gradient-to-r from-green-600 to-green-950 px-6! text-base font-semibold text-white shadow-[0_10px_24px_rgba(21,94,47,0.18)] transition hover:from-green-700 hover:to-green-950 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-green-700/20 disabled:cursor-not-allowed disabled:opacity-65"
              disabled={isSubmitting}
            >
              <LogIn className="h-5 w-5" aria-hidden="true" />
              {isSubmitting ? 'Logging in…' : 'Log In'}
            </button>
          </form>
        </section>
      </section>
    </main>
  );
}
