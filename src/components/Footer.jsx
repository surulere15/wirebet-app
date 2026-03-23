export default function Footer() {
  return (
    <footer className="py-16 border-t border-white/10 bg-[#030303]">
      <div className="max-w-6xl mx-auto px-6 flex flex-col md:flex-row items-center justify-between text-zinc-400 font-medium text-xs uppercase tracking-[0.15em]">
        <p>© {new Date().getFullYear()} Wirebet.</p>
        <div className="flex space-x-12 mt-6 md:mt-0">
          <a href="#" className="hover:text-white transition-colors duration-500">Privacy</a>
          <a href="#" className="hover:text-white transition-colors duration-500">Terms</a>
        </div>
      </div>
    </footer>
  );
}
