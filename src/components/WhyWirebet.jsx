import { motion } from 'framer-motion';

const features = [
  {
    title: "Brand Authority",
    description: "A concise, exact-match identity built to capture market share with zero linguistic friction."
  },
  {
    title: "Sector Alignment",
    description: "Precision-engineered for fast-settlement forecasting, on-chain probability, and institutional liquidity."
  },
  {
    title: "Market Inevitability",
    description: "Establishes immediate operational gravity and definitive credibility from the first impression."
  }
];

export default function WhyWirebet() {
  return (
    <section className="py-40 px-6 bg-background text-center flex flex-col items-center">
      <div className="max-w-6xl mx-auto w-full">
        <motion.div 
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, margin: "-100px" }}
          transition={{ duration: 0.8 }}
          className="mb-24 flex flex-col items-center"
        >
          <div className="w-[1px] h-12 bg-white/30 mb-8" />
          <h2 className="text-3xl md:text-4xl font-display font-normal tracking-wide text-white">Strategic Advantage</h2>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 lg:gap-10">
          {features.map((feature, idx) => (
            <motion.div 
              key={idx}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-100px" }}
              transition={{ duration: 0.8, delay: idx * 0.1 }}
              className="bg-white/[0.02] border border-white/10 p-12 hover:bg-white/[0.04] transition-colors duration-700 flex flex-col items-center text-center group"
            >
              <h3 className="text-lg md:text-xl font-display font-medium text-white mb-6 tracking-wide group-hover:text-white transition-colors">{feature.title}</h3>
              <p className="text-zinc-300 font-normal leading-relaxed tracking-wide text-base">{feature.description}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}
