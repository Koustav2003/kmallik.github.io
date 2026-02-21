import { portfolioData } from '@/data/portfolio';

const Contact = () => {
  return (
    <section id="contact" className="py-20 px-4 md:px-8 bg-gray-50">
      <div className="container mx-auto max-w-4xl">
        <h2 className="text-3xl md:text-4xl font-bold text-gray-900 mb-8 border-b-4 border-isi-green inline-block pb-2">
          Contact
        </h2>

        <div className="bg-white p-8 md:p-12 rounded-lg shadow-lg border border-gray-100">
          <p className="text-xl text-gray-700 leading-relaxed mb-8 text-center md:text-left">
            I am always open to discussing new research opportunities, academic collaborations, or interesting problems in statistics and machine learning.
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div className="space-y-6">
              <div className="flex flex-col">
                <span className="text-sm font-bold text-gray-500 uppercase tracking-wider mb-1">Email</span>
                <a href={`mailto:${portfolioData.personal.email}`} className="text-lg font-medium text-isi-red hover:underline hover:text-red-700 transition">
                  {portfolioData.personal.email}
                </a>
              </div>
              <div className="flex flex-col">
                <span className="text-sm font-bold text-gray-500 uppercase tracking-wider mb-1">Office</span>
                <p className="text-lg text-gray-800">
                  Room 123, Academic Block<br/>
                  {portfolioData.personal.university}
                </p>
              </div>
            </div>

            <div className="space-y-6">
              <div className="flex flex-col">
                <span className="text-sm font-bold text-gray-500 uppercase tracking-wider mb-1">Social</span>
                <div className="flex gap-4">
                  <a href={portfolioData.personal.social.linkedin} className="text-isi-green hover:text-green-800 font-semibold text-lg transition">LinkedIn</a>
                  <a href={portfolioData.personal.social.github} className="text-isi-green hover:text-green-800 font-semibold text-lg transition">GitHub</a>
                  <a href={portfolioData.personal.social.scholar} className="text-isi-green hover:text-green-800 font-semibold text-lg transition">Scholar</a>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};

export default Contact;
