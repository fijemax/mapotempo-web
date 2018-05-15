def arccot(x, unity)
  xpow = unity / x
  n = 1
  sign = 1
  sum = 0
  loop do
   term = xpow / n
   break if term == 0
   sum += sign * (xpow/n)
   xpow /= x*x
   n += 2
   sign = -sign
 end
 sum
end

def calc_pi(digits = 10000)
  fudge = 10
  unity = 10**(digits+fudge)
  pi = 4*(4*arccot(5, unity) - arccot(239, unity))
  pi / (10**fudge)
end

def cpu_rate(digits)
  10.times.map do
    Benchmark.realtime { calc_pi(digits) }
  end.instance_eval { reduce(:+) / size.to_f }
end
