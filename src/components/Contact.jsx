import { motion } from 'framer-motion';

export default function Contact() {
  return (
    <section id="contact" className="py-40 px-6 bg-[#030303] text-center flex flex-col items-center border-t border-white/10">
      <div className="max-w-3xl mx-auto w-full">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8 }}
          className="mb-32 flex flex-col items-center"
        >
          <div className="text-xs uppercase font-medium text-zinc-300 tracking-[0.2em] mb-12">
            Acquisition Protocol
          </div>
          <h2 className="text-2xl md:text-4xl font-display font-normal text-white leading-relaxed max-w-2xl mb-8 tracking-wide">
            Entertaining selective discussions with capitalized operators and strategic acquirers.
          </h2>
          <p className="text-zinc-400 font-normal text-base tracking-wide">
            Direct transfer framework available for qualified principals.
          </p>
        </motion.div>

        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8, delay: 0.2 }}
          className="w-full space-y-10 text-left"
        >
          <div className="mb-16 border-b border-white/20 pb-6">
             <h3 className="text-xl md:text-2xl font-display font-medium text-white mb-3 tracking-wide">Initiate Deal Review</h3>
             <p className="text-zinc-300 text-base font-normal tracking-wide">Secure communication channel for corporate development teams and authorized founders.</p>
          </div>

          <form className="grid grid-cols-1 md:grid-cols-2 gap-y-16 gap-x-12" onSubmit={(e) => e.preventDefault()}>
            <div className="space-y-3 relative group">
              <label className="text-xs uppercase tracking-[0.15em] font-medium text-zinc-300 absolute -top-6 left-0">Principal Name</label>
              <input type="text" className="w-full bg-transparent border-b border-white/30 py-3 text-white focus:outline-none focus:border-white transition-colors duration-500 rounded-none text-base font-normal tracking-wide" />
            </div>
            <div className="space-y-3 relative group">
              <label className="text-xs uppercase tracking-[0.15em] font-medium text-zinc-300 absolute -top-6 left-0">Entity / Fund</label>
              <input type="text" className="w-full bg-transparent border-b border-white/30 py-3 text-white focus:outline-none focus:border-white transition-colors duration-500 rounded-none text-base font-normal tracking-wide" />
            </div>
            <div className="space-y-3 relative group md:col-span-2 mt-4">
              <label className="text-xs uppercase tracking-[0.15em] font-medium text-zinc-300 absolute -top-6 left-0">Corporate Email</label>
              <input type="email" className="w-full bg-transparent border-b border-white/30 py-3 text-white focus:outline-none focus:border-white transition-colors duration-500 rounded-none text-base font-normal tracking-wide" />
            </div>
            <div className="space-y-3 relative group md:col-span-2 mt-4">
              <label className="text-xs uppercase tracking-[0.15em] font-medium text-zinc-300 absolute -top-6 left-0">Mandate Type</label>
              <div className="relative">
                <select className="w-full bg-transparent border-b border-white/30 py-3 text-white focus:outline-none focus:border-white transition-colors duration-500 appearance-none rounded-none text-base font-normal tracking-wide outline-none cursor-pointer">
                  <option value="" className="bg-[#0f0f0f] text-zinc-300">Select parameter...</option>
                  <option value="acquire" className="bg-[#0f0f0f] text-zinc-300">Outright Acquisition</option>
                  <option value="partner" className="bg-[#0f0f0f] text-zinc-300">Strategic Joint Venture</option>
                  <option value="other" className="bg-[#0f0f0f] text-zinc-300">Capital Allocation</option>
                </select>
                <div className="absolute inset-y-0 right-0 flex items-center pointer-events-none text-white/50">
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 9l-7 7-7-7"></path></svg>
                </div>
              </div>
            </div>
            <div className="space-y-3 relative group md:col-span-2 mt-4">
              <label className="text-xs uppercase tracking-[0.15em] font-medium text-zinc-300 absolute -top-6 left-0">Additional Context</label>
              <textarea rows="2" className="w-full bg-transparent border-b border-white/30 py-3 text-white focus:outline-none focus:border-white transition-colors duration-500 resize-none rounded-none text-base font-normal tracking-wide overflow-hidden"></textarea>
            </div>
            <div className="md:col-span-2 mt-12 flex justify-start border-t border-white/10 pt-12">
              <button type="submit" className="px-14 py-5 bg-white text-black font-semibold tracking-[0.1em] text-xs uppercase hover:bg-zinc-200 transition-colors duration-500 rounded-none w-full sm:w-auto text-center">
                Submit Inquiry
              </button>
            </div>
          </form>
        </motion.div>
      </div>
    </section>
  );
}
