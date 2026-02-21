const Footer = () => {
  return (
    <footer className="bg-gray-100 text-gray-700 py-8 mt-16 border-t border-gray-200">
      <div className="container mx-auto px-4 text-center">
        <p className="text-sm">&copy; {new Date().getFullYear()} Master&apos;s Student. All rights reserved.</p>
        <p className="text-sm mt-2 text-gray-500">
          Built with Next.js & Tailwind CSS | Indian Statistical Institute, Kolkata
        </p>
      </div>
    </footer>
  );
};

export default Footer;
