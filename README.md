# qlib-learn

面向 [Qlib](https://github.com/microsoft/qlib) 常用模型的学习笔记。

每篇笔记沿一条主线讲清模型在做什么、公式从哪来、以及对象如何对应到 Qlib 的因子、标签与预测分数。这里不替代官方文档，也不收录完整实验流水线。

## 笔记

| 模型 | 内容 | 源文件 | PDF |
|------|------|--------|-----|
| LightGBM | 从残差、$g,h$ 推到节点目标、$w$、Gain 与区域 $R$ | [`LightGBM-note/lightgbm-math-note.typ`](LightGBM-note/lightgbm-math-note.typ) | [`LightGBM-note/lightgbm-math-note.pdf`](LightGBM-note/lightgbm-math-note.pdf) |

LightGBM 笔记末尾有一节「与 Qlib 股票预测的对应关系」：把 $x$、$y$、$\hat y$、$R_j$、$w_j$ 接到 Alpha158 因子、未来收益标签、预测分数和 TopK 组合。树的叶值 $w_j$ 不是最终持仓权重。

## 编译 Typst 笔记

仓库已附带编译好的 PDF。若要改源文件后重新出 PDF，需要 [Typst](https://typst.app/) 以及正文用到的字体：Noto Serif SC、Noto Sans SC、Cascadia Mono。

```bash
cd LightGBM-note
typst compile lightgbm-math-note.typ lightgbm-math-note.pdf
```
