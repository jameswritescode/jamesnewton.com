# Photo Gallery Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve a small generated WebP thumbnail in the `/photos` grid (instead of the full-res original) so it loads fast on slow connections; clicking a photo still opens the full original in the lightbox.

**Architecture:** On upload, after storing the original, generate a downscaled (longest edge ≤ 1000px) WebP thumbnail via libvips (the `image` lib already in the app) and store it as its own file; a nullable `thumb_key` on `Photo` records it. The public grid serves `thumb_key` (falling back to `image_key`); the lightbox loads the original via a `data-full` attribute. Existing photos are backfilled by an idempotent `Gallery.backfill_thumbnails/0`, wired temporarily into the release migrate step.

**Tech Stack:** Ecto migration, libvips via `image` (`Image.thumbnail/3`, `Image.write/3`), `Newton.Gallery.Storage`, a LiveView upload flow, HEEx + vanilla JS (`photos.js`), Vitest.

**Reference spec:** `docs/superpowers/specs/2026-06-23-gallery-thumbnails-design.md`

**Session constraints:** Commit with `--no-gpg-sign` (the user re-signs later). Don't modify `config/dev.exs`. Servers on PORT=4001. Deploy with `fly deploy --depot=false`.

---

## Task 1: Data model — `thumb_key` column, field, and cast

**Files:**
- Create: `priv/repo/migrations/*_add_thumb_key_to_photos.exs`
- Modify: `lib/newton/gallery/photo.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Write the failing test**

Append to `test/newton/gallery_test.exs` (inside the module; it already aliases `Newton.Gallery` and imports `Newton.GalleryFixtures` — match the file's existing setup):
```elixir
  test "add_photo persists a thumb_key" do
    group = group_fixture()

    {:ok, photo} =
      Gallery.add_photo(group, %{image_key: "k.jpg", thumb_key: "t.webp", alt: "", position: 0})

    assert photo.thumb_key == "t.webp"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/gallery_test.exs` — FAIL (no `thumb_key` field; the key is dropped/unknown).

- [ ] **Step 3: Generate the migration**

Run: `mix ecto.gen.migration add_thumb_key_to_photos`

In the generated file:
```elixir
  def change do
    alter table(:photos) do
      add :thumb_key, :string
    end
  end
```
Run: `mix ecto.migrate`

- [ ] **Step 4: Add the field and cast it (server-set only)**

In `lib/newton/gallery/photo.ex`, add the field after `:image_key`:
```elixir
    field :image_key, :string
    field :thumb_key, :string
```
Add `:thumb_key` to **`create_changeset`** only (it's set by the upload/backfill, like `image_key`) — leave the edit `changeset/2` (which casts only `:alt`) untouched:
```elixir
  def create_changeset(photo, attrs) do
    photo
    |> cast(attrs, [:image_key, :thumb_key, :alt, :position, :width, :height, :photo_group_id])
    |> validate_required([:image_key, :position])
  end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/newton/gallery_test.exs` — PASS.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations lib/newton/gallery/photo.ex test/newton/gallery_test.exs
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add a thumb_key column to photos

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `Newton.Gallery.Thumbnail` — the resize

**Files:**
- Create: `lib/newton/gallery/thumbnail.ex`
- Test: `test/newton/gallery/thumbnail_test.exs`

- [ ] **Step 1: Write the failing test**

`test/newton/gallery/thumbnail_test.exs`:
```elixir
defmodule Newton.Gallery.ThumbnailTest do
  use ExUnit.Case, async: true

  alias Newton.Gallery.Thumbnail

  defp source(w, h) do
    {:ok, img} = Image.new(w, h, color: [40, 30, 20])
    path = Path.join(System.tmp_dir!(), "src-#{System.unique_integer([:positive])}.png")
    {:ok, _} = Image.write(img, path)
    path
  end

  test "downscales the longest edge to 1000 as WebP, preserving aspect ratio" do
    {:ok, thumb_path} = Thumbnail.generate(source(2000, 1500))

    assert Path.extname(thumb_path) == ".webp"
    {:ok, thumb} = Image.open(thumb_path)
    assert Image.width(thumb) == 1000
    assert Image.height(thumb) == 750
  end

  test "does not upscale an image already under the cap" do
    {:ok, thumb_path} = Thumbnail.generate(source(400, 300))

    {:ok, thumb} = Image.open(thumb_path)
    assert Image.width(thumb) == 400
    assert Image.height(thumb) == 300
  end

  test "returns an error for a non-image source" do
    bad = Path.join(System.tmp_dir!(), "bad-#{System.unique_integer([:positive])}.png")
    File.write!(bad, "not an image")

    assert {:error, _} = Thumbnail.generate(bad)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/gallery/thumbnail_test.exs` — FAIL (module missing).

- [ ] **Step 3: Implement the module**

`lib/newton/gallery/thumbnail.ex`:
```elixir
defmodule Newton.Gallery.Thumbnail do
  @moduledoc """
  Generates a downscaled WebP thumbnail of a source image (libvips via the
  `image` lib). Used for the photo grid; the full original is served separately.
  """

  # Longest edge of the thumbnail; downscale-only (never upscales). WebP quality.
  @max_edge 1000
  @quality 75

  @spec generate(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def generate(source_path) do
    dest = Path.join(System.tmp_dir!(), "thumb-#{System.unique_integer([:positive])}.webp")

    with {:ok, thumb} <- Image.thumbnail(source_path, @max_edge, resize: :down),
         {:ok, _} <- Image.write(thumb, dest, quality: @quality) do
      {:ok, dest}
    end
  end
end
```
(`resize: :down` maps to libvips `VIPS_SIZE_DOWN` — shrink only. A single integer length fits the image within `@max_edge` on its longest side, aspect preserved.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/gallery/thumbnail_test.exs` — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/gallery/thumbnail.ex test/newton/gallery/thumbnail_test.exs
git commit --no-gpg-sign -m "$(cat <<'EOF'
Add Gallery.Thumbnail to generate downscaled WebP thumbnails

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `Gallery.store_thumbnail/1` + generate on upload

**Files:**
- Modify: `lib/newton/gallery.ex`, `lib/newton_web/live/admin/gallery_live/show.ex`
- Test: `test/newton_web/live/admin/gallery_show_live_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/newton_web/live/admin/gallery_show_live_test.exs`, add a test that uploads a **real** PNG (the existing upload test uses the string `"fakeimage"`, which can't be thumbnailed; we need real bytes to get a `thumb_key`):
```elixir
  test "uploading a real image stores a thumbnail key", %{conn: conn} do
    group = group_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/photos/#{group.id}")

    {:ok, img} = Image.new(800, 600, color: [10, 20, 30])
    {:ok, png} = Image.write(img, :memory, suffix: ".png")

    photo =
      file_input(view, "#upload-form", :photos, [
        %{name: "real.png", content: png, type: "image/png"}
      ])

    render_hook(view, "set_dimensions", %{"name" => "real.png", "width" => 800, "height" => 600})
    render_upload(photo, "real.png")
    view |> element("#upload-form") |> render_submit()

    [created] = Gallery.get_group!(group.id).photos
    assert is_binary(created.thumb_key)
    assert String.ends_with?(created.thumb_key, ".webp")
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs` — FAIL (`thumb_key` is nil; nothing generates it).

- [ ] **Step 3: Add `Gallery.store_thumbnail/1`**

In `lib/newton/gallery.ex`, add an alias for the new module near the top (alongside the existing `alias Newton.Gallery.{...}`):
```elixir
  alias Newton.Gallery.Thumbnail
```
Add the function (near `add_photo/2`):
```elixir
  @doc """
  Generate a WebP thumbnail of the image at `source_path`, store it, and return
  its key. Cleans up the temp file. Returns `{:error, _}` if the source can't be
  thumbnailed (callers fall back to serving the original).
  """
  @spec store_thumbnail(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def store_thumbnail(source_path) do
    with {:ok, tmp} <- Thumbnail.generate(source_path),
         {:ok, key} <- Storage.store(tmp, "thumb.webp") do
      File.rm(tmp)
      {:ok, key}
    end
  end
```

- [ ] **Step 4: Generate + store the thumbnail on upload**

In `lib/newton_web/live/admin/gallery_live/show.ex` `save_upload`, update the `consume_uploaded_entries` callback and the `Enum.map` to carry/persist `thumb_key`:
```elixir
    uploaded =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        {:ok, key} = Storage.store(path, entry.client_name)

        thumb_key =
          case Gallery.store_thumbnail(path) do
            {:ok, tk} -> tk
            {:error, _} -> nil
          end

        {w, h} = Map.get(dimensions, entry.client_name, {nil, nil})
        {:ok, {key, thumb_key, w, h}}
      end)

    photos =
      uploaded
      |> Enum.with_index(base)
      |> Enum.map(fn {{key, thumb_key, w, h}, position} ->
        {:ok, photo} =
          Gallery.add_photo(group, %{
            image_key: key,
            thumb_key: thumb_key,
            alt: "",
            position: position,
            width: w,
            height: h
          })

        photo
      end)
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/gallery_show_live_test.exs` — PASS (both the new test and the pre-existing `"fakeimage"` upload test, which now exercises the `thumb_key: nil` fallback).

- [ ] **Step 6: Commit**

```bash
git add lib/newton/gallery.ex lib/newton_web/live/admin/gallery_live/show.ex test/newton_web/live/admin/gallery_show_live_test.exs
git commit --no-gpg-sign -m "$(cat <<'EOF'
Generate and store a thumbnail when a photo is uploaded

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Public grid serves the thumbnail; lightbox loads the original

**Files:**
- Modify: `lib/newton/gallery.ex`, `lib/newton_web/controllers/photo_html.ex`, `lib/newton_web/controllers/photo_html/index.html.heex`, `assets/js/photos.js`
- Test: `assets/js/photos.test.js`

- [ ] **Step 1: Write the failing JS test**

In `assets/js/photos.test.js`, add to the `describe("photo lightbox", …)` block:
```javascript
  it("loads the original from data-full, not the grid thumbnail", () => {
    document.body.innerHTML = `
      <div class="photo-grid" id="grid-a">
        <button class="photo-button" data-index="0" data-full="orig.jpg">
          <img src="thumb.webp" alt="A" />
        </button>
      </div>
      <div class="photo-overlay" id="photoOverlay" inert>
        <button type="button" class="photo-overlay-close" aria-label="Close">&times;</button>
        <img class="photo-overlay-img" id="photoOverlayImg" alt="" />
      </div>`
    initPhotos()

    click(document.querySelector(".photo-button"))

    const full = document.getElementById("photoOverlayImg")
    expect(full.getAttribute("src")).toBe("orig.jpg")
    expect(full.alt).toBe("A")
  })
```
(`initPhotos`, `click` are already imported/defined at the top of the file.)

- [ ] **Step 2: Run it to verify it fails**

Run: `cd assets && pnpm test photos` — FAIL (the lightbox uses `img.src` = `thumb.webp`, not `orig.jpg`).

- [ ] **Step 3: Point the lightbox at `data-full`**

In `assets/js/photos.js`, update `show`:
```javascript
  const show = (btn) => {
    currentButton = btn;
    const img = btn.querySelector("img");
    full.src = btn.dataset.full || img.src;
    full.alt = img.alt;
  };
```

- [ ] **Step 4: Run the JS test to verify it passes**

Run: `cd assets && pnpm test photos` — PASS.

- [ ] **Step 5: Add `Gallery.thumb_url/1` and delegate it**

In `lib/newton/gallery.ex`:
```elixir
  @doc "Grid URL for a photo: its thumbnail if present, else the original."
  @spec thumb_url(%Photo{}) :: String.t()
  def thumb_url(%Photo{thumb_key: thumb_key, image_key: image_key}),
    do: image_url(thumb_key || image_key)
```
In `lib/newton_web/controllers/photo_html.ex`, alongside the existing `defdelegate image_url(key), to: Newton.Gallery`:
```elixir
  defdelegate thumb_url(photo), to: Newton.Gallery
```

- [ ] **Step 6: Update the grid template**

In `lib/newton_web/controllers/photo_html/index.html.heex`, change the button + img so the grid loads the thumbnail and the button carries the original:
```heex
        <button
          :for={{photo, index} <- Enum.with_index(group.photos)}
          type="button"
          class="photo-button"
          data-index={index}
          data-full={image_url(photo.image_key)}
          aria-label={"Enlarge: #{photo.alt}"}
        >
          <img
            src={thumb_url(photo)}
            loading="lazy"
            decoding="async"
            alt={photo.alt}
            width={photo.width}
            height={photo.height}
          />
        </button>
```
(Keep `width`/`height` = the original dimensions — the thumbnail has the same aspect ratio, so the layout reservation is unchanged.)

- [ ] **Step 7: Run the suite + commit**

Run: `mix test test/newton_web/controllers/photo_controller_test.exs` (if present) or `mix test` — PASS. Run: `cd assets && pnpm test` — PASS.
```bash
git add lib/newton/gallery.ex lib/newton_web/controllers/photo_html.ex lib/newton_web/controllers/photo_html/index.html.heex assets/js/photos.js assets/js/photos.test.js
git commit --no-gpg-sign -m "$(cat <<'EOF'
Serve thumbnails in the photo grid; open the original in the lightbox

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Delete the thumbnail file with the photo

**Files:**
- Modify: `lib/newton/gallery.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/newton/gallery_test.exs` (the module already has `alias Newton.Gallery.Storage` and `import Newton.GalleryFixtures`). Add these two private helpers near the top of the module:
```elixir
  defp store_original do
    {:ok, img} = Image.new(1200, 900, color: [9, 9, 9])
    src = Path.join(System.tmp_dir!(), "orig-#{System.unique_integer([:positive])}.png")
    {:ok, _} = Image.write(img, src)
    {:ok, key} = Storage.store(src, "orig.png")
    File.rm(src)
    key
  end

  defp media_path(key), do: Path.join(Application.fetch_env!(:newton, :media_root), key)

  test "delete_photo removes both the original and the thumbnail files" do
    group = group_fixture()
    image_key = store_original()
    {:ok, thumb_key} = Gallery.store_thumbnail(media_path(image_key))

    {:ok, photo} =
      Gallery.add_photo(group, %{
        image_key: image_key,
        thumb_key: thumb_key,
        alt: "",
        position: 0
      })

    assert File.exists?(media_path(image_key))
    assert File.exists?(media_path(thumb_key))

    {:ok, _} = Gallery.delete_photo(photo)

    refute File.exists?(media_path(image_key))
    refute File.exists?(media_path(thumb_key))
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/gallery_test.exs` — FAIL (the thumbnail file is left on disk; only the original is deleted).

- [ ] **Step 3: Delete the thumbnail in both delete paths**

In `lib/newton/gallery.ex`:
```elixir
  def delete_group(%PhotoGroup{} = group) do
    group = Repo.preload(group, :photos)

    Enum.each(group.photos, fn photo ->
      Storage.delete(photo.image_key)
      Storage.delete(photo.thumb_key)
    end)

    Repo.delete(group)
  end
```
```elixir
  def delete_photo(%Photo{} = photo) do
    Storage.delete(photo.image_key)
    Storage.delete(photo.thumb_key)
    Repo.delete(photo)
  end
```
(`Storage.delete/1` already no-ops on `nil`, so photos without a thumbnail are fine.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/newton/gallery_test.exs` — PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/newton/gallery.ex test/newton/gallery_test.exs
git commit --no-gpg-sign -m "$(cat <<'EOF'
Delete a photo's thumbnail file along with the original

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Backfill existing photos + wire into the release

**Files:**
- Modify: `lib/newton/gallery.ex`, `lib/newton/release.ex`
- Test: `test/newton/gallery_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/newton/gallery_test.exs` (reuses `store_original/0` and `media_path/1` from Task 5):
```elixir
  test "backfill_thumbnails generates thumbnails for photos missing them, idempotently" do
    group = group_fixture()
    image_key = store_original()
    {:ok, photo} = Gallery.add_photo(group, %{image_key: image_key, alt: "", position: 0})
    assert is_nil(photo.thumb_key)

    assert %{ok: 1, failed: 0} = Gallery.backfill_thumbnails()

    reloaded = Gallery.get_photo!(photo.id)
    assert is_binary(reloaded.thumb_key)
    assert File.exists?(media_path(reloaded.thumb_key))

    # Already done — a second run is a no-op.
    assert %{ok: 0, failed: 0} = Gallery.backfill_thumbnails()
  end

  test "backfill_thumbnails counts a photo whose original is missing as failed" do
    group = group_fixture()
    {:ok, _} = Gallery.add_photo(group, %{image_key: "missing.jpg", alt: "", position: 0})

    assert %{ok: 0, failed: 1} = Gallery.backfill_thumbnails()
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton/gallery_test.exs` — FAIL (`backfill_thumbnails/0` undefined).

- [ ] **Step 3: Implement `backfill_thumbnails/0`**

In `lib/newton/gallery.ex` add `require Logger` near the top (after the aliases), then:
```elixir
  @doc """
  Generate + store a thumbnail for every photo that doesn't have one yet.
  Idempotent (skips photos with a `thumb_key`); logs and continues past
  per-photo failures. Returns counts.
  """
  @spec backfill_thumbnails() :: %{ok: non_neg_integer(), failed: non_neg_integer()}
  def backfill_thumbnails do
    Photo
    |> where([p], is_nil(p.thumb_key))
    |> Repo.all()
    |> Enum.reduce(%{ok: 0, failed: 0}, fn photo, acc ->
      source = Path.join(media_root(), photo.image_key)

      with true <- File.exists?(source),
           {:ok, key} <- store_thumbnail(source),
           {:ok, _} <- photo |> Ecto.Changeset.change(thumb_key: key) |> Repo.update() do
        Map.update!(acc, :ok, &(&1 + 1))
      else
        _ ->
          Logger.error("thumbnail backfill failed for photo #{photo.id} (#{photo.image_key})")
          Map.update!(acc, :failed, &(&1 + 1))
      end
    end)
  end

  defp media_root, do: Application.fetch_env!(:newton, :media_root)
```
(`gallery.ex` already `import`s `Ecto.Query`, so `where/3` is available.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/gallery_test.exs` — PASS.

- [ ] **Step 5: Wire the backfill into the release migrate step (temporary)**

In `lib/newton/release.ex`, extend `migrate/0` so the release runs the backfill after migrations (it runs on the next deploy; idempotent so harmless thereafter):
```elixir
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    # TEMPORARY: backfill thumbnails for photos uploaded before this feature.
    # Remove this block after the first deploy that includes it (Task 7).
    {:ok, _, _} =
      Ecto.Migrator.with_repo(Repo, fn _repo -> Newton.Gallery.backfill_thumbnails() end)

    :ok
  end
```
Note: `migrate/0`'s `@spec` returns `[{:ok, list(), list()}]`; it now returns `:ok`. Update the spec to `@spec migrate() :: :ok`.

- [ ] **Step 6: Run precommit + commit**

Run: `mix precommit` — green (the release change is covered by compile/dialyzer; the backfill by its tests).
```bash
git add lib/newton/gallery.ex lib/newton/release.ex test/newton/gallery_test.exs
git commit --no-gpg-sign -m "$(cat <<'EOF'
Backfill thumbnails for existing photos via the release migrate step

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Verify, deploy, and remove the temporary backfill

- [ ] **Step 1: Local end-to-end (PORT=4001)** — `mix precommit` green; start the server, upload a photo in the admin gallery, and confirm: the grid `<img src>` is a `…​.webp` thumbnail, the `<button data-full>` is the original `/media/<image_key>`, clicking opens the original, and the thumbnail file is much smaller than the original.

- [ ] **Step 2: Deploy** — `fly deploy --depot=false`. The release `migrate` runs the schema migration (adds `thumb_key`) **and** `backfill_thumbnails/0`, generating thumbnails for the existing gallery photos automatically.

- [ ] **Step 3: Confirm prod** — load `https://jamesnewton-com.fly.dev/photos`; grid images are `…​.webp`; a backfilled photo's `<img>` src differs from its `data-full` (thumbnail vs original); clicking loads the original. Optionally check the deploy's release-command logs for the backfill (no errors).

- [ ] **Step 4: Remove the temporary backfill from the release** — once prod is confirmed backfilled, revert the `migrate/0` change from Task 6 Step 5 (drop the backfill block; restore the original `@spec`/return). New uploads generate their own thumbnails, so nothing further needs it; `Gallery.backfill_thumbnails/0` stays as a manually-runnable function.
```bash
git add lib/newton/release.ex
git commit --no-gpg-sign -m "$(cat <<'EOF'
Remove the one-time thumbnail backfill from the release step

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```
Then `fly deploy --depot=false` again so the release no longer runs the backfill.

---

## Self-review notes

- **Spec coverage:** data model (Task 1); `Thumbnail` resize (Task 2); upload generation via `store_thumbnail` (Task 3); grid `thumb_url` + `data-full` + lightbox (Task 4); both delete paths remove the thumb (Task 5); idempotent backfill + release wiring (Task 6); verification, deploy, and removal of the temporary backfill (Task 7). Error handling (generation failure → `thumb_key: nil` fallback) is implemented in `store_thumbnail`/`Thumbnail.generate` and exercised by Task 3's pre-existing `"fakeimage"` test and Task 6's missing-source test.
- **Consistency:** `Thumbnail.generate/1` → `Gallery.store_thumbnail/1` → `thumb_key` is the same key threaded through `add_photo`, the grid (`thumb_url/1`), the delete paths, and the backfill. `data-full` (set in the template) is exactly what `photos.js` reads. `@max_edge 1000` / `@quality 75` live only in `Thumbnail`.
- **Tunables:** thumbnail size/quality are the two named constants in `Newton.Gallery.Thumbnail`.
