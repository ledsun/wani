const panel = document.querySelector('.speaker-columns article');
const content = document.querySelector('#speaker-slide-content');
let scheduled = false;

function fitSlide() {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    content.style.zoom = '1';
    const style = getComputedStyle(panel);
    const width = panel.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    const height = panel.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
    const scale = Math.min(1, width / content.scrollWidth, height / content.scrollHeight);
    if (Number.isFinite(scale) && scale > 0) content.style.zoom = String(scale);
  });
}

new ResizeObserver(fitSlide).observe(panel);
new MutationObserver(fitSlide).observe(content, { childList: true, characterData: true, subtree: true });
content.addEventListener('load', fitSlide, true);
document.fonts.ready.then(fitSlide);
