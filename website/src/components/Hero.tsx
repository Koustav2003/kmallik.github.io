import Link from 'next/link';
import { portfolioData } from '@/data/portfolio';

const Hero = () => {
  return (
    <section className="bg-gray-50 py-20 px-4 md:px-8 border-b border-gray-200">
      <div className="container mx-auto flex flex-col md:flex-row items-center gap-10">
        <div className="md:w-1/3 flex justify-center">
          {/* Placeholder for Profile Image */}
          <div className="w-48 h-48 md:w-64 md:h-64 bg-gray-300 rounded-full flex items-center justify-center text-gray-500 font-bold border-4 border-white shadow-lg overflow-hidden">
            <span className="text-xl">Your Photo</span>
          </div>
        </div>
        <div className="md:w-2/3 text-center md:text-left space-y-6">
          <h1 className="text-4xl md:text-6xl font-bold text-gray-900 tracking-tight">
            {portfolioData.personal.name}
          </h1>
          <h2 className="text-xl md:text-2xl text-isi-green font-medium">
            {portfolioData.personal.role}
          </h2>
          <p className="text-lg text-gray-700 max-w-2xl mx-auto md:mx-0 leading-relaxed">
            {portfolioData.personal.bio}
          </p>
          <div className="flex flex-col sm:flex-row justify-center md:justify-start gap-4 pt-4">
            <Link
              href="#contact"
              className="px-8 py-3 bg-isi-red text-white font-bold rounded shadow hover:bg-red-700 transition transform hover:-translate-y-1"
            >
              Get in Touch
            </Link>
            <Link
              href="#research"
              className="px-8 py-3 border-2 border-isi-green text-isi-green font-bold rounded shadow-sm hover:bg-green-50 transition transform hover:-translate-y-1"
            >
              View Research
            </Link>
          </div>
        </div>
      </div>
    </section>
  );
};

export default Hero;
