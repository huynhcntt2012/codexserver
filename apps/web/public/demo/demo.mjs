const frame = document.querySelector('#game');
frame.addEventListener('load', () => frame.focus());
document.querySelector('#fullscreen').addEventListener('click', async () => {
  try {
    await frame.requestFullscreen();
  } catch {
    frame.focus();
  }
});
