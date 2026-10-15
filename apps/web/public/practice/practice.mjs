const frame = document.querySelector('#game');
document.querySelector('#start').addEventListener('click', () => {
  document.querySelector('#intro').hidden = true;
  document.querySelector('#help').hidden = false;
  frame.hidden = false;
  frame.src = '/practice/engine/index.html';
  frame.focus();
});
document.querySelector('#fullscreen').addEventListener('click', async () => {
  if (!frame.hidden && frame.requestFullscreen) {
    try {
      await frame.requestFullscreen();
    } catch {
      frame.focus();
    }
  }
});
