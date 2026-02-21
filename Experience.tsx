import { portfolioData } from '@/data/portfolio';

const Experience = () => {
  return (
    <section id="experience" className="py-20 px-4 md:px-8 bg-white">
      <div className="container mx-auto max-w-4xl">
        <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-12 border-b-4 border-isi-green inline-block pb-2">
          Experience & Education
        </h2>
        
        <div className="space-y-16">
          {/* Education Section */}
          <div>
             <h3 className="text-2xl font-bold text-gray-800 mb-8 flex items-center gap-3">
              <span className="w-2 h-8 bg-isi-red rounded-sm"></span>
              Education
            </h3>
            <div className="relative border-l-2 border-gray-200 ml-3 space-y-12">
              {portfolioData.education.map((edu, index) => (
                <div key={index} className="ml-8 relative">
                  <span className="absolute -left-[41px] top-1 h-5 w-5 rounded-full border-4 border-white bg-isi-green shadow-sm"></span>
                  <div className="bg-gray-50 p-6 rounded-lg border border-gray-100 shadow-sm hover:shadow-md transition-shadow">
                    <h4 className="text-xl font-bold text-gray-900">{edu.degree}</h4>
                    <p className="text-isi-green font-semibold mb-2">{edu.institution} <span className="text-gray-400 mx-2">|</span> {edu.year}</p>
                    <ul className="list-disc pl-5 text-gray-700 space-y-1 mt-3">
                      {edu.details.map((detail, idx) => (
                        <li key={idx}>{detail}</li>
                      ))}
                    </ul>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Work Experience Section */}
          {portfolioData.work.length > 0 && (
            <div>
              <h3 className="text-2xl font-bold text-gray-800 mb-8 flex items-center gap-3">
                <span className="w-2 h-8 bg-isi-red rounded-sm"></span>
                Professional Experience
              </h3>
              <div className="relative border-l-2 border-gray-200 ml-3 space-y-12">
                {portfolioData.work.map((job, index) => (
                  <div key={index} className="ml-8 relative">
                    <span className="absolute -left-[41px] top-1 h-5 w-5 rounded-full border-4 border-white bg-isi-green shadow-sm"></span>
                    <div className="bg-gray-50 p-6 rounded-lg border border-gray-100 shadow-sm hover:shadow-md transition-shadow">
                      <h4 className="text-xl font-bold text-gray-900">{job.position}</h4>
                      <p className="text-isi-green font-semibold mb-2">{job.company} <span className="text-gray-400 mx-2">|</span> {job.year}</p>
                      <ul className="list-disc pl-5 text-gray-700 space-y-1 mt-3">
                        {job.details.map((detail, idx) => (
                          <li key={idx}>{detail}</li>
                        ))}
                      </ul>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          <div className="flex justify-center pt-8">
            <a 
              href={portfolioData.personal.resume} 
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center px-8 py-3 bg-isi-green text-white font-bold rounded-full shadow-lg hover:bg-green-700 transition transform hover:-translate-y-1 gap-2"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>
              Download Full Resume
            </a>
          </div>

        </div>
      </div>
    </section>
  );
};

export default Experience;
