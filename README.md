# BioNexus Android Starter

A first Flutter MVP for the BioNexus scientific species encyclopedia.

## Included in this starter
- Home screen and navigation
- Search by scientific name, common name, Bengali name, phylum and genus
- Species detail pages with taxonomy
- Bengali/English interface toggle
- Light/dark mode
- Local in-app sample dataset
- Local favorites during the current app session

## Important limitations
This is an MVP starter, not the complete production application.
Favorites are currently in memory and reset when the app restarts.
The sample data is illustrative and must be checked against authoritative taxonomy sources.
Cloud sync, Supabase, persistent SQLite, authentication, real audio, images, and admin tools are planned next.

## Build
Use the included GitHub Actions workflow to build an APK in the cloud.

## Features
- 400+ species with full classification (Kingdom to Species), Bengali, English and Japanese names
- Interface in English, Bengali and Japanese
- Quick quiz (scientific names, common names, families, orders)
- Explore filter by group (plants, animals, fungi, bacteria, viruses, protists)

## Adding more species
All species live in `assets/species.json`. Add a new block like this (comma between blocks):

```json
{
  "scientific": "Panthera leo",
  "common": "Lion",
  "bangla": "সিংহ",
  "japanese": "ライオン",
  "kingdom": "Animalia",
  "phylum": "Chordata",
  "class": "Mammalia",
  "order": "Carnivora",
  "family": "Felidae",
  "pronunciation": "PAN-thuh-ruh LEE-oh",
  "description": "Optional short overview."
}
```
`genus` and `species` are filled in automatically from the scientific name. `japanese`, `pronunciation` and `description` are optional (the app falls back to the English name).
Commit to `main` and GitHub Actions builds a new APK. Verify every entry against GBIF / ITIS / Catalogue of Life.
