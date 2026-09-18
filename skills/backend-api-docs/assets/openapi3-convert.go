// Command openapi3 把 swag 產出的 Swagger 2.0 中間產物（tmp/swagger/swagger.json）轉成 OpenAPI 3.0（docs/openapi3.json）。
// 由 make swagger 在產生 Swagger 之後執行；3.0 是唯一進版控的規格，也是給前端、其他開發者與 AI 工具使用的正本。
package main

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/getkin/kin-openapi/openapi2"
	"github.com/getkin/kin-openapi/openapi2conv"
	"github.com/getkin/kin-openapi/openapi3"
)

const (
	source = "tmp/swagger/swagger.json"
	target = "docs/openapi3.json"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "openapi3:", err)
		os.Exit(1)
	}
	fmt.Println("create openapi3.json at " + target)
}

func run() error {
	raw, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	var v2 openapi2.T
	if err := json.Unmarshal(raw, &v2); err != nil {
		return fmt.Errorf("decode %s: %w", source, err)
	}
	v3, err := openapi2conv.ToV3(&v2)
	if err != nil {
		return fmt.Errorf("convert: %w", err)
	}
	// swag 以 x-nullable 標記可為 null 的欄位（Swagger 2.0 沒有 nullable），轉成 3.0 的 nullable
	for _, ref := range v3.Components.Schemas {
		applyNullable(ref)
	}
	for _, path := range v3.Paths.Map() {
		for _, op := range path.Operations() {
			if op.RequestBody != nil && op.RequestBody.Value != nil {
				for _, media := range op.RequestBody.Value.Content {
					applyNullable(media.Schema)
				}
			}
			for _, resp := range op.Responses.Map() {
				if resp.Value == nil {
					continue
				}
				for _, media := range resp.Value.Content {
					applyNullable(media.Schema)
				}
			}
		}
	}
	out, err := json.MarshalIndent(v3, "", "    ")
	if err != nil {
		return err
	}
	return os.WriteFile(target, append(out, '\n'), 0o644)
}

// applyNullable 把 x-nullable 擴充轉成 nullable，並移除擴充；遞迴處理巢狀 schema（不跟隨 $ref，元件本身會各自處理）。
func applyNullable(ref *openapi3.SchemaRef) {
	if ref == nil || ref.Value == nil {
		return
	}
	s := ref.Value
	if v, ok := s.Extensions["x-nullable"]; ok {
		if b, ok := v.(bool); ok && b {
			s.Nullable = true
		}
		delete(s.Extensions, "x-nullable")
	}
	for _, child := range s.Properties {
		applyNullable(child)
	}
	applyNullable(s.Items)
	applyNullable(s.AdditionalProperties.Schema)
	for _, child := range append(append(append([]*openapi3.SchemaRef{}, s.AllOf...), s.AnyOf...), s.OneOf...) {
		applyNullable(child)
	}
}
