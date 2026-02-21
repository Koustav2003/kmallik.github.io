import Hero from '@/components/Hero';
import About from '@/components/About';
import Experience from '@/components/Experience';
import Research from '@/components/Research';
import Projects from '@/components/Projects';
import Contact from '@/components/Contact';

export default function Home() {
  return (
    <div className="flex flex-col gap-0">
      <Hero />
      <About />
      <Experience />
      <Research />
      <Projects />
      <Contact />
    </div>
  );
}
