import { portfolioData } from '@/data/portfolio';

const About = () => {
  return (
    <section id="about" className="py-20 px-4 md:px-8 bg-white">
      <div className="container mx-auto max-w-4xl">
        <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-8 border-b-4 border-isi-green inline-block pb-2">
          About Me
        </h2>
        <div className="prose prose-lg text-gray-700 max-w-none">
          {portfolioData.personal.longBio.map((paragraph, index) => (
            <p key={index} className="mb-6 leading-relaxed">
              {paragraph}
            </p>
          ))}
          
          <p className="mb-6 leading-relaxed">
            With a strong foundation in mathematics and statistics, my research interests primarily focus on:
          </p>
          <ul className="list-disc pl-6 mb-6 space-y-2 marker:text-isi-red">
            <li>Statistical Inference and Modeling</li>
            <li>Machine Learning and AI</li>
            <li>Computational Statistics</li>
            <li>Data Visualization</li>
          </ul>
        </div>
      </div>
    </section>
  );
};

export default About;
