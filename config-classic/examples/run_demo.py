"""GaussianVim run panel demo: press F5.

Top of the card: the iteration messages appear live.
Middle: the result and the files the run wrote (Enter opens them).
Bottom: the plot, drawn inside the card (z opens it as a real window with
zoom / pan / save). q hides the card, Q closes it.
"""
import time

import matplotlib.pyplot as plt
import numpy as np
rng = np.random.default_rng(0)
steps = rng.normal(size=(2000, 400))
walk = np.zeros(len(steps))
for i in range(1, 11):
    walk = steps[:, : i * 40].sum(axis=1)
    print(f"step {i * 40:4d}: mean = {walk.mean():+.3f}, std = {walk.std():.3f}  (expected {np.sqrt(i * 40):.3f})")
    time.sleep(0.3)

np.savetxt("walk_endpoints.csv", walk, delimiter=",", header="endpoint", comments="")
print("saved walk_endpoints.csv")

x = np.linspace(walk.min(), walk.max(), 300)
sigma = np.sqrt(steps.shape[1])
plt.hist(walk, bins=50, density=True, alpha=0.6, label="2000 random walks")
plt.plot(x, np.exp(-x**2 / (2 * sigma**2)) / (sigma * np.sqrt(2 * np.pi)), lw=2, label="Gaussian")
plt.title("Central limit theorem")
plt.legend()
plt.savefig("clt.png", dpi=120)
plt.show()
ppStatsint("done")
