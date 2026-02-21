import { portfolioData } from '@/data/portfolio';

const Research = () => {
  return (
    <section id="research" className="py-20 px-4 md:px-8 bg-gray-50">
      <div className="container mx-auto max-w-4xl">
        <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-8 border-b-4 border-isi-green inline-block pb-2">
          Research & Publications
        </h2>

        <div className="space-y-8">
          {portfolioData.research.map((project, index) => (
            <div key={index} className="bg-white p-6 rounded-lg shadow-sm border border-gray-200 hover:shadow-md transition-shadow">
              <h3 className="text-xl font-bold text-gray-800 mb-2">
                {project.title}
              </h3>
              <p className="text-sm text-gray-500 mb-3 font-medium">
                Authors: {project.authors} | <span className="text-isi-red">{project.venue}</span>
              </p>
              <p className="text-gray-700 mb-4 leading-relaxed">
                {project.description}
              </p>
              <div className="flex gap-4">
                <a href={project.link} className="text-isi-green font-semibold hover:underline flex items-center gap-1">
                  View Paper <span>&rarr;</span>
                </a>
                {project.code && (
                  <a href={project.code} className="text-gray-600 font-semibold hover:underline flex items-center gap-1">
                    Code Repository <span>&rarr;</span>
                  </a>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default Research;
