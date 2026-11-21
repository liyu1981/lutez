export function renderNotFound() {
  return `<main id="main" class="notfound">
  <p class="eyebrow">404</p>
  <h1>This branch didn’t match.</h1>
  <p class="lede">The page you’re looking for isn’t in the AST. Try the docs or the playground.</p>
  <div class="hero-cta">
    <a class="btn btn-primary" href="./docs/">Browse docs</a>
    <a class="btn btn-ghost" href="./demo/">Open demo</a>
  </div>
</main>`;
}
