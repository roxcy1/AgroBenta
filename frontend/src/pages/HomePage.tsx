import {
  BadgeCheck,
  ChartNoAxesCombined,
  Download,
  MapPin,
  MessagesSquare,
  ReceiptText,
  Sparkles,
  Store,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import './HomePage.css';

interface Feature {
  icon: LucideIcon;
  title: string;
  description: string;
}

// Every statement here describes behaviour the system already has (functional
// documentation §3–§8). No figures, testimonials or sample listings: the page
// must not present invented data as real.
const FEATURES: Feature[] = [
  {
    icon: Store,
    title: 'Livestock marketplace',
    description:
      'Browse listings by livestock type, barangay and price. Each listing shows the breed, age, weight, health status and photos.',
  },
  {
    icon: BadgeCheck,
    title: 'Verified sellers',
    description:
      'Sellers submit a valid ID, proof of address and a selfie. An administrator reviews every application before a seller can list.',
  },
  {
    icon: Sparkles,
    title: 'AI-based price suggestion',
    description:
      'Sellers see a suggested price as a reference when preparing a listing. The seller always sets the final asking price.',
  },
  {
    icon: MessagesSquare,
    title: 'Inquiries and messaging',
    description:
      'Ask the seller a question or send an inquiry, then agree on the price, payment and pickup or delivery in one conversation.',
  },
  {
    icon: ReceiptText,
    title: 'Tracked transactions',
    description:
      'Follow a purchase from preparation to pickup or delivery. The buyer confirms receipt and gets a digital purchase receipt.',
  },
  {
    icon: ChartNoAxesCombined,
    title: 'Data analytics',
    description:
      'Administrators review listings and see marketplace activity, sales trends and livestock distribution in the Admin Web.',
  },
];

const BUYER_STEPS = [
  'Create an account. Every account starts as a buyer.',
  'Browse the marketplace and open a listing.',
  'Ask the seller a question, or send an inquiry.',
  'Accept the seller’s offer and arrange pickup or delivery.',
  'Confirm you received the livestock and keep the receipt.',
];

const SELLER_STEPS = [
  'Apply for seller verification from your account.',
  'Wait for an administrator to review your documents.',
  'Create a listing and check the suggested price.',
  'Submit the listing. It appears once it is approved.',
  'Answer inquiries, send an offer and complete the sale.',
];

const LIVESTOCK_TYPES = ['Cattle', 'Carabao', 'Goat', 'Swine', 'Chicken'];

/**
 * The mobile app is not released yet, so this is deliberately not a link and
 * performs no action. It is a real disabled button, so assistive technology
 * announces it as unavailable, and the label says why.
 */
function DownloadButton({ variant }: { variant: 'on-dark' | 'on-light' }) {
  return (
    <button
      type="button"
      className={`home-download home-download--${variant}`}
      disabled
      aria-describedby="home-download-note"
    >
      <Download className="home-download-icon" aria-hidden="true" />
      <span className="home-download-text">
        <span className="home-download-label">Download for Android</span>
        <span className="home-download-status">Coming soon</span>
      </span>
    </button>
  );
}

// The page carries no link to the admin console on purpose: it is the public
// face of the product. Administrators open /login directly.
export default function HomePage() {
  return (
    <div className="home">
      <a className="home-skip-link" href="#main">
        Skip to main content
      </a>

      <header className="home-nav">
        <div className="home-container home-nav-inner">
          <a className="home-brand" href="#top" aria-label="AgroBenta home">
            <span className="home-brand-agro">Agro</span>
            <span className="home-brand-benta">Benta</span>
          </a>
          <nav className="home-nav-links" aria-label="Page sections">
            <a href="#features">Features</a>
            <a href="#how-it-works">How it works</a>
            <a href="#livestock">Livestock</a>
            <a href="#download">Download</a>
          </nav>
        </div>
      </header>

      <main id="main">
        <section className="home-hero" id="top">
          <div className="home-container home-hero-inner">
            <div className="home-hero-copy">
              <p className="home-eyebrow">
                <MapPin className="home-eyebrow-icon" aria-hidden="true" />
                Municipality of Trinidad, Bohol
              </p>
              <h1 className="home-hero-title">
                Buy and sell livestock with people you can trust.
              </h1>
              <p className="home-hero-lead">
                AgroBenta is a mobile livestock marketplace for Trinidad. Farmers
                list their animals, buyers find them nearby, and every seller is
                verified first.
              </p>
              <div className="home-hero-actions">
                <DownloadButton variant="on-dark" />
                <a className="home-button home-button--ghost" href="#how-it-works">
                  See how it works
                </a>
              </div>
              <p className="home-hero-note" id="home-download-note">
                The mobile app is still in development. The download will open
                here when it is released.
              </p>
            </div>
            <div className="home-hero-art">
              <img
                className="home-hero-logo"
                src="/images/agrobenta-logo.png"
                alt="AgroBenta logo"
                width={1536}
                height={1024}
              />
              <p className="home-hero-tagline">Buy. Sell. Grow. Together.</p>
            </div>
          </div>
        </section>

        <section className="home-section" id="features" aria-labelledby="features-title">
          <div className="home-container">
            <header className="home-section-header">
              <h2 className="home-section-title" id="features-title">
                What AgroBenta does
              </h2>
              <p className="home-section-lead">
                One app for listing, finding and trading livestock, with checks
                that protect both sides.
              </p>
            </header>
            <ul className="home-feature-grid">
              {FEATURES.map(({ icon: Icon, title, description }) => (
                <li className="home-feature" key={title}>
                  <span className="home-feature-icon" aria-hidden="true">
                    <Icon />
                  </span>
                  <h3 className="home-feature-title">{title}</h3>
                  <p className="home-feature-text">{description}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section
          className="home-section home-section--tinted"
          id="how-it-works"
          aria-labelledby="how-title"
        >
          <div className="home-container">
            <header className="home-section-header">
              <h2 className="home-section-title" id="how-title">
                How it works
              </h2>
              <p className="home-section-lead">
                One account does both. You start as a buyer and can apply to
                sell at any time.
              </p>
            </header>
            <div className="home-steps-grid">
              <article className="home-steps" aria-labelledby="buyer-steps-title">
                <h3 className="home-steps-title" id="buyer-steps-title">
                  For buyers
                </h3>
                <ol className="home-steps-list">
                  {BUYER_STEPS.map((step) => (
                    <li key={step}>{step}</li>
                  ))}
                </ol>
              </article>
              <article className="home-steps" aria-labelledby="seller-steps-title">
                <h3 className="home-steps-title" id="seller-steps-title">
                  For sellers
                </h3>
                <ol className="home-steps-list">
                  {SELLER_STEPS.map((step) => (
                    <li key={step}>{step}</li>
                  ))}
                </ol>
              </article>
            </div>
          </div>
        </section>

        <section className="home-section" id="livestock" aria-labelledby="livestock-title">
          <div className="home-container home-livestock">
            <header className="home-section-header home-section-header--left">
              <h2 className="home-section-title" id="livestock-title">
                Livestock you can trade
              </h2>
              <p className="home-section-lead">
                Listings are organized by type, so buyers find the right animal
                quickly.
              </p>
            </header>
            <ul className="home-livestock-list">
              {LIVESTOCK_TYPES.map((type) => (
                <li key={type}>{type}</li>
              ))}
            </ul>
          </div>
        </section>

        <section className="home-cta" id="download" aria-labelledby="download-title">
          <div className="home-container home-cta-inner">
            <div>
              <h2 className="home-cta-title" id="download-title">
                Get the AgroBenta mobile app
              </h2>
              <p className="home-cta-text">
                For Android phones. The app is being finished and tested, and
                is not available to download yet.
              </p>
            </div>
            <DownloadButton variant="on-light" />
          </div>
        </section>
      </main>

      <footer className="home-footer">
        <div className="home-container">
          <p className="home-brand home-brand--footer">
            <span className="home-brand-agro">Agro</span>
            <span className="home-brand-benta">Benta</span>
          </p>
          <p className="home-footer-text">
            A mobile-based livestock trading application with AI-based price
            suggestion, seller verification and data analytics, for the
            Municipality of Trinidad, Bohol.
          </p>
        </div>
      </footer>
    </div>
  );
}
