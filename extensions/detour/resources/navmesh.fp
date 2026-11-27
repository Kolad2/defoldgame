uniform lowp vec4 tint;
void main() {
    gl_FragColor = vec4(tint.rgb * tint.a, tint.a);
}
