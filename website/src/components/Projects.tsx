import { portfolioData } from '@/data/portfolio';

const Projects = () => {
  return (
    <section id="projects" className="py-20 px-4 md:px-8 bg-white">
      <div className="container mx-auto max-w-4xl">
        <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-8 border-b-4 border-isi-green inline-block pb-2">
          Projects
        </h2>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          {portfolioData.projects.map((project, index) => (
            <div key={index} className="bg-gray-50 p-6 rounded-xl border border-gray-200 shadow-sm hover:shadow-lg transition-shadow duration-300">
              <h3 className="text-2xl font-bold text-gray-800 mb-2">
                {project.title}
              </h3>
              <p className="text-sm text-isi-red font-semibold uppercase tracking-wide mb-4">
                {project.stack}
              </p>
              <p className="text-gray-700 mb-6 leading-relaxed">
                {project.description}
              </p>
              <a href={project.link} className="inline-flex items-center text-isi-green font-bold hover:underline gap-1">
                View on GitHub <span>&rarr;</span>
              </a>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default Projects;
