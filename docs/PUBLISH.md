# Publish to GitHub (v0.3.0)

Local repo is ready at `C:\1C\projects\1c-ninja-kit` (branch `main`, tag suggested `v0.3.0`).

## On a machine with `gh` authenticated

```powershell
cd C:\1C\projects\1c-ninja-kit
gh auth login
gh repo create 1c-ninja-kit --public --source=. --remote=origin --push
git tag v0.3.0
git push origin v0.3.0
```

Or private:

```powershell
gh repo create 1c-ninja-kit --private --source=. --remote=origin --push
```

## On laptop (clone + test)

```powershell
git clone https://github.com/<USER_OR_ORG>/1c-ninja-kit.git
cd 1c-ninja-kit
# then MACHINE-BOOTSTRAP + TEST-GUIDE-deepseek or hermes
```

## Testers

- DeepSeek: `docs/PASTE-TO-DEEPSEEK.txt` + `docs/TEST-GUIDE-deepseek.md`
- Hermes: `docs/PASTE-TO-HERMES.txt` + `docs/TEST-GUIDE-hermes.md`
