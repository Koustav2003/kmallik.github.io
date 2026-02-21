import Link from 'next/link';
import { portfolioData } from '@/data/portfolio';

const Header = () => {
  return (
    <header className="bg-isi-green text-white shadow-md sticky top-0 z-50">
      <div className="container mx-auto px-4 py-4 flex flex-col md:flex-row justify-between items-center">
        <Link href="/" className="text-2xl font-bold mb-4 md:mb-0 hover:text-gray-200 transition-colors">
          {portfolioData.personal.name}
        </Link>
        <nav>
          <ul className="flex flex-wrap justify-center space-x-6">
            <li><Link href="#about" className="hover:text-gray-200 transition-colors">About</Link></li>
            <li><Link href="#experience" className="hover:text-gray-200 transition-colors">Experience</Link></li>
            <li><Link href="#research" className="hover:text-gray-200 transition-colors">Research</Link></li>
            <li><Link href="#projects" className="hover:text-gray-200 transition-colors">Projects</Link></li>
            <li><Link href="#contact" className="hover:text-gray-200 transition-colors">Contact</Link></li>
          </ul>
        </nav>
      </div>
    </header>
  );
};

export default Header;
