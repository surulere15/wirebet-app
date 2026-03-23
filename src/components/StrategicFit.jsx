import { motion } from 'framer-motion';

const targets = [
  { title: "On-Chain Wagering Protocol", description: "Secure definitive market positioning and accelerate global user acquisition." },
  { title: "Decentralized Prediction Market", description: "Anchor complex forecasting algorithms with a highly accessible consumer identity." },
  { title: "Institutional Liquidity Exchange", description: "Signal institutional-grade execution speed and instantaneous settlement architecture." },
  { title: "Wagering Infrastructure Provider", description: "Deliver B2B or B2C platform solutions under a commanding tier-one moniker." }
];

export default function StrategicFit() {
  return (
    <section className="py-40 px-6 bg-background flex flex-col items-center border-t border-white/10">
      <div className="max-w-5xl mx-auto w-full space-y-20">
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8 }}
          className="text-center flex flex-col items-center"
        >
          <div className="w-[1px] h-12 bg-white/30 mb-8" />
          <h2 className="text-3xl md:text-4xl font-display font-normal tracking-wide text-white">Target Acquirers</h2>
        </motion.div>

        <motion.div 
          className="grid grid-cols-1 md:grid-cols-2 gap-px bg-white/20 overflow-hidden"
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 1, delay: 0.2 }}
        >
          {targets.map((target, idx) => (
            <div key={idx} className="bg-[#050505] group p-12 hover:bg-[#0a0a0a] transition-colors duration-700 flex flex-col justify-center min-h-[200px] border-[0.5px] border-transparent hover:z-10 relative cursor-default">
               <h3 className="text-xl md:text-2xl font-normal tracking-wide text-white mb-4 group-hover:-translate-y-1 transition-transform duration-500">{target.title}</h3>
               <p className="text-base font-normal text-zinc-400 tracking-wide leading-relaxed group-hover:text-zinc-200 transition-colors duration-500">{target.description}</p>
            </div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
