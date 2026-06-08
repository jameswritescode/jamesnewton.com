alias Newton.{Repo, Blog, Reading, Gallery}
alias Newton.Blog.Post
alias Newton.Reading.Entry
alias Newton.Gallery.{PhotoGroup, Photo}

# Idempotent reset (dev/placeholder content only)
Repo.delete_all(Photo)
Repo.delete_all(PhotoGroup)
Repo.delete_all(Entry)
Repo.delete_all(Post)

# --- Posts ---
three_ways = """
Retry logic is one of those small utilities every codebase eventually needs. The network flakes. A database is briefly unreachable. An upstream service returns a `503` and a polite suggestion to try again. We reach for a helper, and — if we're lucky — one already exists.

What's interesting isn't the logic itself. [Exponential backoff with jitter](https://en.wikipedia.org/wiki/Exponential_backoff) is more or less a solved problem. What's interesting is how different the *shape* of the solution looks in different languages. The same idea, expressed three ways, tells you something about what each language thinks a good abstraction feels like.

## The problem

Let's pick a concrete target. We want a helper that:

- Takes a function that might fail
- Retries up to `n` times with exponential backoff
- Gives up on errors that are clearly not transient
- Returns the successful value — or the final error

Three languages, three takes. Same idea.

## Python: decorators and duck typing

Python leans on decorators for this kind of cross-cutting concern. The call site stays clean; the retry policy sits above the function like an annotation.

```python
import time
import random
from functools import wraps

def retry(attempts=3, base_delay=0.5):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            last_error = None
            for attempt in range(attempts):
                try:
                    return fn(*args, **kwargs)
                except TransientError as e:
                    last_error = e
                    delay = base_delay * (2 ** attempt) + random.random() * 0.1
                    time.sleep(delay)
            raise last_error
        return wrapper
    return decorator

@retry(attempts=5)
def fetch_user(user_id: str) -> User:
    return api.get(f"/users/{user_id}")
```

The decorator is readable at the call site — `@retry(attempts=5)` reads almost like a sentence. But it hides control flow. A reader has to know what `retry` does, and whether `TransientError` is the right thing to catch.

## TypeScript: async functions and higher-order functions

In TypeScript, retry usually shows up as a higher-order function wrapping a promise. The types do a lot of work: the generic flows through, and the caller gets back exactly what they put in.

```typescript
type RetryOptions = {
  attempts?: number;
  baseDelayMs?: number;
  isTransient?: (err: unknown) => boolean;
};

async function retry<T>(
  fn: () => Promise<T>,
  { attempts = 3, baseDelayMs = 500, isTransient = () => true }: RetryOptions = {},
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (!isTransient(err)) throw err;
      lastError = err;
      const delay = baseDelayMs * 2 ** attempt + Math.random() * 100;
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw lastError;
}

const user = await retry(() => fetchUser(userId), { attempts: 5 });
```

The call site is noisier than Python's — you pass a lambda — but the generic `<T>` means no casting, and the options bag is self-documenting. The `isTransient` predicate is a nice touch: it pushes the "what counts as retryable?" decision to the caller, where it usually belongs.

## Go: explicit loops, explicit errors

Go doesn't hide control flow, and retry is no exception. You write the loop. You check the error. It's verbose in the way Go is usually verbose — deliberately.

```go
func Retry[T any](
    ctx context.Context,
    attempts int,
    baseDelay time.Duration,
    fn func() (T, error),
) (T, error) {
    var zero T
    var lastErr error
    for attempt := 0; attempt < attempts; attempt++ {
        result, err := fn()
        if err == nil {
            return result, nil
        }
        if !isTransient(err) {
            return zero, err
        }
        lastErr = err
        delay := baseDelay * (1 << attempt)
        select {
        case <-ctx.Done():
            return zero, ctx.Err()
        case <-time.After(delay):
        }
    }
    return zero, lastErr
}

user, err := Retry(ctx, 5, 500*time.Millisecond, func() (User, error) {
    return fetchUser(userId)
})
```

The call site carries weight: you pass a context, a count, a delay, a closure. You get back a value *and* an error. But notice what the extra verbosity buys you — cancellation via `ctx`, which the other two versions quietly ignore. Go makes you write it, but it also makes you think about it.

At a glance, the three versions trade off differently:

| Language | Idiom | Call site | Cancellation |
|---|---|---|---|
| Python | Decorator | Terse | Implicit |
| TypeScript | Higher-order | Options bag | Via `AbortSignal` |
| Go | Generic loop | Verbose | Explicit `ctx` |

![A whiteboard sketch of three boxes connected by arrows, representing different retry implementations](https://images.unsplash.com/photo-1519389950473-47ba0277781c?w=720&q=80)

---

## What the shapes reveal

> The same idea becomes three different objects depending on what the language considers idiomatic: a decorator, a higher-order function, a generic loop.

None of these is wrong. They reflect different values. Python prizes **terseness at the call site**. TypeScript leans on **types as documentation**. Go insists that **control flow stay visible**.

When you write retry logic in a language, you're not just solving the transient-failure problem. You're choosing which costs to pay — readability, explicitness, flexibility, safety — and the language has already made some of those choices for you.

That, I think, is the quiet lesson of looking at the same thing three ways. A language isn't just syntax. It's a stance on what good code feels like — and the small utilities are where the stance shows up most clearly. If you want to feel the difference, write your own [retry helper](https://github.com/search?q=retry+language%3ATypeScript&type=repositories) in a language you haven't used in a while. The language will teach you what it values.
"""

{:ok, _} =
  Blog.create_post(%{
    slug: "three-ways-to-retry",
    title: "Three Ways to Retry",
    body_markdown: three_ways,
    published_at: ~U[2026-04-17 12:00:00Z]
  })

quiet_shift = """
There was a time when writing software felt like building a cathedral. Every function was a brick laid with intention, every module an arch designed to bear weight. The craft demanded patience — hours spent tracing a bug through layers of abstraction, days spent debating the right name for a method. It was slow, deliberate, and deeply human.

That era hasn't ended, exactly. But it has begun to blur at the edges.

## The New Apprentice

AI-driven development arrived not with a bang but with a tab-completion. First it suggested a line. Then a function. Then an entire module, scaffolded and tested before the engineer had finished their coffee. The tools were good — unnervingly good — and they got better at a pace that made roadmaps feel quaint.

For many teams, the shift was pragmatic. Why spend an afternoon wiring up boilerplate when a model could do it in seconds? The velocity gains were real and immediate. Sprints that once crawled now sprinted. Features that lived on wishlists materialized in days.

## What Remains

But velocity is not the same as understanding. The engineer who writes a sorting algorithm by hand may be slower than the one who prompts for it, but they carry something the latter does not: an intuition for when things will break. They know the shape of the problem because they've traced its contours with their own hands.

Architecture is still a human art. Knowing which abstraction to reach for, when to split a service, how to name things so the next person isn't lost — these are judgment calls that resist automation. They require taste, context, and a kind of empathy for the future reader that no model has yet demonstrated convincingly.

## What's at Risk

The danger isn't that AI writes bad code. It often writes perfectly adequate code. The danger is that we stop understanding what adequate means. When the feedback loop between writing and understanding is broken — when code is generated rather than authored — we lose the instinct that tells us something is subtly wrong.

Debugging, too, is a casualty. The deep, meditative practice of stepping through execution, holding state in your head, forming and discarding hypotheses — this is where engineers develop their sharpest instincts. If we outsource it entirely, we may find ourselves unable to diagnose the failures that matter most: the ones the AI didn't anticipate.

## A Way Forward

The answer is probably not resistance. The tools are too useful, the pressure too real. But it might be intentionality. Use the AI to handle the tedious, the repetitive, the well-understood. But keep your hands in the soil for the work that matters — the design decisions, the tricky edge cases, the code that will outlive the sprint.

Software engineering has always been about managing complexity with clarity. The tools change. The craft endures — if we choose to practice it.
"""

{:ok, _} =
  Blog.create_post(%{
    slug: "the-quiet-shift-software-engineering-in-the-age-of-ai",
    title: "The Quiet Shift: Software Engineering in the Age of AI",
    body_markdown: quiet_shift,
    published_at: ~U[2026-04-14 12:00:00Z]
  })

# --- Reading ---
reading = [
  %{
    title: "A Philosophy of Software Design",
    author: "John Ousterhout",
    status: :read,
    finished_at: ~D[2026-04-18],
    note:
      "The argument for deep modules stuck with me. I don't fully agree, but I keep returning to it."
  },
  %{
    title: "Working in Public",
    author: "Nadia Eghbal",
    status: :listened,
    finished_at: ~D[2026-04-13]
  },
  %{
    title: "The Pragmatic Programmer",
    author: "Hunt and Thomas",
    status: :read,
    finished_at: ~D[2026-03-15]
  },
  %{
    title: "Designing Data-Intensive Applications",
    author: "Martin Kleppmann",
    status: :read,
    finished_at: ~D[2026-02-22],
    note:
      "The kind of book you read a chapter at a time, put down, and notice it quietly reshaping how you think about the system you work on."
  },
  %{
    title: "Four Thousand Weeks",
    author: "Oliver Burkeman",
    status: :read,
    finished_at: ~D[2026-01-18],
    note: "I don't know if I believed all of it. I kept putting it down to think."
  },
  %{
    title: "The Mythical Man-Month",
    author: "Fred Brooks",
    status: :read,
    finished_at: ~D[2025-12-08]
  },
  %{
    title: "The Creative Act",
    author: "Rick Rubin",
    status: :listened,
    finished_at: ~D[2025-11-10],
    note:
      "Rubin reads the audiobook himself, which is the right call. A good one for a long walk."
  },
  %{title: "Atomic Habits", author: "James Clear", status: :read, finished_at: ~D[2025-10-03]},
  %{
    title: "Shop Class as Soulcraft",
    author: "Matthew B. Crawford",
    status: :read,
    finished_at: ~D[2025-09-14]
  },
  %{
    title: "Zen and the Art of Motorcycle Maintenance",
    author: "Robert Pirsig",
    status: :listened,
    finished_at: ~D[2025-08-06],
    note: "Most of it went past me. The pages about caring for a machine did not."
  }
]

Enum.each(reading, fn attrs -> {:ok, _} = Reading.create_entry(attrs) end)

# --- Photos (dev uses remote URLs as image_key; image_url/1 passes them through) ---
photo_groups = [
  %{
    slug: "eastern-sierra",
    title: "Eastern Sierra",
    taken_on: ~D[2025-06-01],
    caption:
      "Four days of granite and alpine water, on the route up from Onion Valley I'd been circling for a year.",
    photos: [
      {"https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80",
       "Morning light breaking over a mountain ridge"},
      {"https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=800&q=80",
       "Still alpine lake reflecting distant peaks"},
      {"https://images.unsplash.com/photo-1454496522488-7a8e488e8606?w=800&q=80",
       "Stone cabin at the edge of a mountain lake"},
      {"https://images.unsplash.com/photo-1475924156734-496f6cac6ec1?w=800&q=80",
       "Snow-dusted peaks above a quiet lake"}
    ]
  },
  %{
    slug: "olympic-coast",
    title: "Olympic Coast",
    taken_on: ~D[2025-03-01],
    caption:
      "Fog kept rewriting the shoreline as overlapping silhouettes — which, it turns out, is the thing I came back for.",
    photos: [
      {"https://images.unsplash.com/photo-1486870591958-9b9d0d1dda99?w=800&q=80",
       "Fog rolling between forested ridgelines"},
      {"https://images.unsplash.com/photo-1472214103451-9374bd1c798e?w=800&q=80",
       "Evergreen forest shrouded in morning mist"},
      {"https://images.unsplash.com/photo-1513836279014-a89f7a76ae86?w=800&q=80",
       "Tall pine trees catching afternoon light"},
      {"https://images.unsplash.com/photo-1519904981063-b0cf448d479e?w=800&q=80",
       "Dense fog clinging to mountain slopes"}
    ]
  },
  %{
    slug: "julian-alps",
    title: "Julian Alps",
    taken_on: ~D[2025-01-01],
    caption:
      "Lake Bled was still frozen at the edges. The trails around Triglav I kept cutting short for weather.",
    photos: [
      {"https://images.unsplash.com/photo-1508739773434-c26b3d09e071?w=800&q=80",
       "Winter forest, snow on every branch"},
      {"https://images.unsplash.com/photo-1519681393784-d120267933ba?w=800&q=80",
       "Night sky over a silhouetted mountain ridge"},
      {"https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=800&q=80",
       "Lake Bled at dusk with an island chapel"},
      {"https://images.unsplash.com/photo-1433086966358-54859d0ed716?w=800&q=80",
       "Suspension bridge over a pine-lined gorge"}
    ]
  },
  %{
    slug: "dolomites",
    title: "Dolomites",
    taken_on: ~D[2024-09-01],
    caption:
      "The via ferrata I came for was closed for weather. I spent the week walking between huts instead.",
    photos: [
      {"https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&q=80",
       "Snow-capped alpine peaks at sunrise"},
      {"https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=800&q=80",
       "Sun setting behind layered mountain ridges"},
      {"https://images.unsplash.com/photo-1443890923422-7819ed4101c0?w=800&q=80",
       "A lone tent pitched beneath a granite wall"},
      {"https://images.unsplash.com/photo-1454372182658-c712e4c5a1db?w=800&q=80",
       "Narrow valley with a winding river"}
    ]
  }
]

Enum.each(photo_groups, fn %{photos: photos} = attrs ->
  {:ok, group} = Gallery.create_group(Map.delete(attrs, :photos))

  photos
  |> Enum.with_index(1)
  |> Enum.each(fn {{key, alt}, pos} ->
    {:ok, _} = Gallery.add_photo(group, %{image_key: key, alt: alt, position: pos})
  end)
end)

IO.puts(
  "Seeded #{Repo.aggregate(Post, :count)} posts, #{Repo.aggregate(Entry, :count)} reading entries, #{Repo.aggregate(PhotoGroup, :count)} photo groups."
)
