export interface PortfolioData {
  personal: {
    name: string;
    role: string;
    university: string;
    email: string;
    location: string;
    bio: string;
    longBio: string[];
    resume: string;
    social: {
      linkedin: string;
      github: string;
      scholar: string;
    };
  };
  education: {
    degree: string;
    institution: string;
    year: string;
    details: string[];
  }[];
  work: {
    position: string;
    company: string;
    year: string;
    details: string[];
  }[];
  research: {
    title: string;
    authors: string;
    venue: string;
    description: string;
    link: string;
    code?: string;
  }[];
  projects: {
    title: string;
    stack: string;
    description: string;
    link: string;
  }[];
}

export const portfolioData: PortfolioData = {
  personal: {
    name: "Your Name",
    role: "Master's Candidate in Statistics",
    university: "Indian Statistical Institute, Kolkata",
    email: "student@isical.ac.in",
    location: "Kolkata, India",
    bio: "Passionate about data science, machine learning, and statistical analysis. Currently pursuing my Master's at the Indian Statistical Institute, Kolkata.",
    longBio: [
      "I am currently a Master's student at the prestigious Indian Statistical Institute (ISI), Kolkata. My academic journey is driven by a curiosity to understand complex systems through data and mathematics.",
      "With a strong foundation in mathematics and statistics, my research interests primarily focus on Statistical Inference, Machine Learning, and Computational Statistics.",
      "When I'm not working on research or coursework, I enjoy exploring new technologies, contributing to open-source projects, and reading about advancements in the field."
    ],
    resume: "/resume.pdf",
    social: {
      linkedin: "#",
      github: "#",
      scholar: "#"
    }
  },
  education: [
    {
      degree: "Master of Statistics (M.Stat)",
      institution: "Indian Statistical Institute, Kolkata",
      year: "2024 - Present",
      details: ["Specialization in Computational Statistics", "Current CGPA: 9.0/10"]
    },
    {
      degree: "Bachelor of Science (Honours) in Mathematics",
      institution: "Your Undergraduate University",
      year: "2021 - 2024",
      details: ["Graduated with First Class Honours", "Awarded Best Student in Mathematics"]
    }
  ],
  work: [
    {
      position: "Research Intern",
      company: "Tech Company / Research Lab",
      year: "Summer 2024",
      details: ["Developed a machine learning model for anomaly detection.", "Collaborated with a team of 5 researchers to publish findings."]
    }
  ],
  research: [
    {
      title: "Title of Your Research Paper",
      authors: "You, Collaborator A, Collaborator B",
      venue: "Conference/Journal Name (Year)",
      description: "A brief abstract or description of the research. Explain the problem, methodology, and key findings.",
      link: "#",
      code: "#"
    },
    {
      title: "Another Research Title",
      authors: "You, Supervisor Name",
      venue: "Under Review / Working Paper (Year)",
      description: "Description of another significant research project. Highlight the impact and your specific contributions.",
      link: "#"
    }
  ],
  projects: [
    {
      title: "Data Analysis Toolkit",
      stack: "Python • Pandas • Matplotlib",
      description: "A Python library designed to simplify exploratory data analysis for large datasets. Includes automated visualization and statistical summaries.",
      link: "#"
    },
    {
      title: "Machine Learning Model",
      stack: "TensorFlow • Keras • React",
      description: "Implemented a deep learning model for image classification, achieving 95% accuracy on standard benchmarks. Deployed with a React frontend.",
      link: "#"
    }
  ]
};
