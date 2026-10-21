/* ==========================================================================
   PixOS — Interactive Landing Page Scripts
   Copyright (c) 2026 Exactable | MIT License
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
    // 1. Interactive Simulator Toggles
    const togglePills = document.querySelectorAll('.sim-toggle-pill');
    togglePills.forEach(pill => {
        pill.addEventListener('click', () => {
            pill.classList.toggle('active');
            const chk = pill.querySelector('.chk');
            if (chk) {
                chk.textContent = pill.classList.contains('active') ? '✓' : '';
            }
        });
    });

    // 2. Simulated Progress Bar Animation
    const progressFill = document.querySelector('.sim-progress-fill');
    if (progressFill) {
        let percent = 68;
        setInterval(() => {
            percent += (Math.random() * 2 - 0.5);
            if (percent > 98) percent = 45;
            if (percent < 40) percent = 40;
            progressFill.style.width = `${percent.toFixed(1)}%`;
        }, 1200);
    }

    // 3. Smooth Anchor Scrolling
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const targetId = this.getAttribute('href');
            if (targetId && targetId !== '#') {
                const targetElem = document.querySelector(targetId);
                if (targetElem) {
                    e.preventDefault();
                    targetElem.scrollIntoView({
                        behavior: 'smooth',
                        block: 'start'
                    });
                }
            }
        });
    });

    // 4. Parallax effect on ambient glow orbs
    window.addEventListener('mousemove', (e) => {
        const mouseX = e.clientX / window.innerWidth - 0.5;
        const mouseY = e.clientY / window.innerHeight - 0.5;

        const glow1 = document.querySelector('.glow-1');
        const glow2 = document.querySelector('.glow-2');

        if (glow1) {
            glow1.style.transform = `translate(${mouseX * 40}px, ${mouseY * 40}px)`;
        }
        if (glow2) {
            glow2.style.transform = `translate(${mouseX * -30}px, ${mouseY * -30}px)`;
        }
    });
});
