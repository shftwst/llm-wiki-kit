# llm-wiki-gen

Your business already has the answers. They're just buried in folders, inboxes, and someone's
head. This makes that pile answerable: ask a question in plain words, get an answer pulled from
your own documents, not from a guess. Where's the signed contract? What rate did we agree? Who
did we use for insurance last year?

Finding a fact stops being an afternoon of digging. And when the person who knew everything is
on holiday, or gone, the knowledge stays.

You don't tag, sort, or file anything. You drop documents in a folder; an AI reads them, writes
them into a tidy set of linked notes, and keeps it current as you add more. The filing is its
job, not yours. (Based on Andrej Karpathy's **LLM Wiki** pattern,
[`docs/llm-wiki-pattern.md`](docs/llm-wiki-pattern.md).)

## Nothing new to learn

Most of these systems die because they ask everyone to tag and tidy, and people quietly stop.
Here there's one folder. Drop a file in, walk away, that's the whole job. Share it as a network
folder and it's the only thing anyone touches; the rest stays out of sight. Because there's
nothing to learn, it actually gets used, which is the only reason any of this is worth doing.

It doesn't fight how you already work, either. Keep your files in the cloud exactly as you do
now, point it at them, and it adds the connections a folder of files can never show you: who a
contract is with, which rate replaced which, where two documents disagree.

## Your files are safe

Nothing you put in ever gets changed. The system can read your documents but is physically
blocked from editing, moving, or deleting them. The AI can't either, even when it's running on
its own overnight. Point it at a shared drive someone else keeps tidy and it reads through to
the originals without touching them, picking up edits whenever they happen. No "the computer
reorganised my files" disaster waiting to go off.

(For whoever sets it up: a Claude Code hook, `scripts/guard-raw`, enforces this on the `raw/`
folder; sources can be plain files or symlinks to living documents.)

## Answers you can actually trust

A knowledge base is worthless if you can't believe it. Every answer traces back to the real
document it came from, so you can check it yourself. When two documents disagree it says so,
instead of quietly picking one and hoping. It re-reads the sources to mark its own homework, and
flags anything it can't back up rather than inventing something to fill the gap.

It's careful with your money, too: it reads the important things first (you say what matters),
sets obvious junk aside for you to glance at rather than deleting it, and when it's unsure it
keeps a document, because losing something real is worse than holding onto something useless.

## It gets to know your business

The more you use it, the better it gets. It reads deeper over time, remembers your corrections,
and saves the answers to questions you've already asked so the next person gets them straight
away. After a while it knows your suppliers, your clients, and your quirks, and the answers come
faster and sharper.

## Quiet and cheap

It only does paid work when something actually changed; an ordinary day with nothing new costs
nothing. It looks for new files itself and gets on with it, no babysitting. Run it by hand or
leave it on a schedule (`scripts/ingest --auto`).

## The right people see the right things

You decide who sees what. Sensitive material (anything with personal or financial detail) can
stay on a computer in your own office and never be sent anywhere. And you can hand someone a
plain read-only website of the knowledge, filtered to their level: a client sees only
client-safe pages, your staff see more, you see everything, with private bits and any path back
to the original files stripped out. (`scripts/publish <role>`, with sensitivity tagging from
`scripts/classify`.)

## Setting one up

Each knowledge base is a self-contained folder, and its own git repo. Create one with:

```sh
./scripts/new-kb my-kb "My Knowledge Base Title"              # creates ../my-kb/
./scripts/new-kb my-kb "My KB Title" /path/to/parent-dir     # or elsewhere
```

Inside it's plain files: `wiki/` (the notes), `raw/` (your documents), `inbox/` (the drop
folder), `.schema/` (page types and privacy levels), and a running `log.md`. The AI's full
instructions live in `AGENTS.md`, the writing rules in `STYLE.md`. Edit `_template/` to change
what new bases look like. Every script, in detail:
[`_template/scripts/README.md`](_template/scripts/README.md).

## License

Apache 2.0, see [LICENSE](LICENSE).
