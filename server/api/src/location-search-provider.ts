export interface LocationSuggestion {
  id: string;
  address: string;
}

export interface LocationSearchProvider {
  search(query: string): Promise<LocationSuggestion[]>;
}

export class EmptyLocationSearchProvider implements LocationSearchProvider {
  async search(): Promise<LocationSuggestion[]> { return []; }
}

export class GooglePlacesLocationSearchProvider implements LocationSearchProvider {
  constructor(private readonly apiKey: string) {}

  async search(query: string): Promise<LocationSuggestion[]> {
    const response = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": this.apiKey,
        "X-Goog-FieldMask": "suggestions.placePrediction.placeId,suggestions.placePrediction.text",
      },
      body: JSON.stringify({ input: query, includedRegionCodes: ["us"] }),
    });
    if (!response.ok) throw new Error(`Google Places request failed with ${response.status}`);
    const payload = await response.json() as GooglePlacesResponse;
    return (payload.suggestions ?? []).flatMap((suggestion) => {
      const prediction = suggestion.placePrediction;
      return prediction?.placeId && prediction.text?.text
        ? [{ id: prediction.placeId, address: prediction.text.text }]
        : [];
    });
  }
}

interface GooglePlacesResponse {
  suggestions?: Array<{
    placePrediction?: {
      placeId?: string;
      text?: { text?: string };
    };
  }>;
}
