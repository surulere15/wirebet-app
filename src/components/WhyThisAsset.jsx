import { motion } from 'framer-motion';

const points = [
  "Universally recognizable across global jurisdictions",
  "Native alignment with high-velocity speculation rails",
  "Agnostic utility across Web3 and traditional fiat markets",
  "Derisks market entry by accelerating brand trust"
];

export default function WhyThisAsset() {
  return (
    <section className="py-24 px-6 bg-background flex flex-col items-center border-t border-white/10">
      <div className="max-w-4xl mx-auto w-full flex flex-col md:flex-row gap-16 md:gap-24 items-start">
        <motion.div 
          initial={{ opacity: 0, x: -20 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8 }}
          className="md:w-1/3 shrink-0"
        >
          <h2 className="text-2xl md:text-3xl font-display font-normal tracking-wide text-white">Asset Profile</h2>
          <p className="text-zinc-400 font-normal mt-4 text-base tracking-wide leading-relaxed">Fundamental acquisition rationale.</p>
        </motion.div>
        
        <motion.div 
          className="md:w-2/3 flex flex-col w-full"
          initial={{ opacity: 0, x: 20 }}
          whileInView={{ opacity: 1, x: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8, delay: 0.2 }}
        >
          {points.map((point, idx) => (
            <div key={idx} className="flex items-center gap-6 py-6 border-b border-white/10 group last:border-0">
              <span className="text-sm font-mono font-medium text-zinc-400 group-hover:text-white transition-colors duration-500">{(idx + 1).toString().padStart(2, '0')}</span>
              <p className="text-base md:text-lg font-normal text-zinc-200 tracking-wide group-hover:text-white transition-colors duration-500">
                {point}
              </p>
            </div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
