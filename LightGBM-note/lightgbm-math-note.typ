// LightGBM 数学推导讲义
// 编译：typst compile lightgbm-math-note.typ lightgbm-math-note.pdf

#set document(
  title: "LightGBM 数学推导：从残差到树结构",
  author: "学习笔记",
  date: datetime.today(),
)

#set page(
  paper: "a4",
  margin: (top: 20mm, bottom: 18mm, x: 22mm),
  numbering: "1",
  header: context {
    if counter(page).get().first() > 1 {
      set text(size: 8.5pt, fill: luma(105))
      grid(
        columns: (1fr, auto),
        [LightGBM 数学推导],
        [从 $g,h$ 到节点目标与 Gain],
      )
      line(length: 100%, stroke: 0.35pt + luma(190))
    }
  },
)

#set text(
  font: "Noto Serif SC",
  lang: "zh",
  region: "cn",
  size: 10.5pt,
)
#set par(first-line-indent: 2em, leading: 0.78em, justify: true)
#set heading(numbering: "1.1")
#set math.equation(numbering: "(1)")
#show raw: set text(font: ("Cascadia Mono", "Noto Sans SC"), size: 9pt)
#show link: underline

#show heading: it => {
  v(0.7em)
  set par(first-line-indent: 0em)
  if it.level == 1 {
    block(
      width: 100%,
      inset: (bottom: 4pt),
      stroke: (bottom: 0.8pt + rgb("355a7a")),
    )[
      #text(size: 15pt, weight: "semibold", fill: rgb("244a65"))[
        #if it.numbering != none {
          context counter(heading).display(it.numbering)
          h(0.7em)
        }
        #it.body
      ]
    ]
  } else {
    text(size: 12pt, weight: "semibold", fill: rgb("244a65"))[
      #if it.numbering != none {
        context counter(heading).display(it.numbering)
        h(0.65em)
      }
      #it.body
    ]
  }
}

#let key-box(title, body) = block(
  width: 100%,
  fill: rgb("eef5f8"),
  stroke: 0.7pt + rgb("8db5c7"),
  radius: 4pt,
  inset: 10pt,
  breakable: true,
)[
  #set par(first-line-indent: 0em)
  #text(weight: "semibold", fill: rgb("244a65"))[#title]
  #v(3pt)
  #body
]

#let intuition(body) = block(
  width: 100%,
  fill: luma(247),
  stroke: (left: 2.5pt + rgb("d49b43")),
  inset: (left: 11pt, right: 9pt, y: 8pt),
  breakable: true,
)[
  #set par(first-line-indent: 0em)
  #text(weight: "semibold", fill: rgb("8b5a18"))[直觉]
  #h(0.6em)#body
]

#align(center)[
  #v(9mm)
  #text(size: 22pt, weight: "bold", fill: rgb("244a65"))[
    LightGBM 数学推导
  ]
  #v(4pt)
  #text(size: 14pt, fill: rgb("52758c"))[
    从残差、$g,h$ 到节点目标、$w$、Gain 与区域 $R$
  ]
  #v(10mm)
]

#block(
  width: 100%,
  inset: (x: 14pt, y: 11pt),
  fill: luma(247),
  radius: 4pt,
)[
  #set par(first-line-indent: 0em)
  *摘要：* 本讲义沿一条连续主线推导 LightGBM。已有 $m-1$ 棵树时，我们增加第 $m$ 棵树。新树同时包含叶节点区域 $R_1,dots,R_J$ 与叶节点输出 $w_1,dots,w_J$。损失函数在当前预测处展开后，一阶导数 $g$ 描述修正方向，二阶导数 $h$ 描述局部曲率。把同一叶节点内的样本聚合起来，就得到节点目标函数；对它求导可得最优 $w_j$，比较分裂前后的最优目标值则得到 Gain。平方损失下，整个推导会退化为一个熟悉结论：每个叶节点拟合该区域内的平均残差。
]

#v(7mm)

#key-box([全文路线], [
  $ hat(y)_n^((m-1))
    arrow.r
    f_(m)(bold(x)) = sum_j w_j bb(1)(bold(x) in R_j)
    arrow.r
    (g_n, h_n)
    arrow.r
    cal(L)_(j)(w_j)
    arrow.r
    w_j^star
    arrow.r
    "Gain"
    arrow.r
    R_j $
])

#v(4mm)
#heading(numbering: none)[目录]
#{
  set text(size: 8.4pt)
  set par(leading: 0.45em, first-line-indent: 0em)
  columns(2, gutter: 7mm)[
    #outline(title: none, depth: 2)
  ]
}
#pagebreak()

= 符号与问题设置

设训练集为

$
cal(D) = { (bold(x)_n, y_n) }_(n=1)^N,
$

其中 $bold(x)_n in RR^p$ 是第 $n$ 个样本的特征向量，$y_n$ 是监督目标。在 Qlib 的股票预测任务中，一个样本通常对应“某只股票在某个交易日”，$bold(x)_n$ 是 Alpha158 等因子，$y_n$ 是未来收益标签。

#figure(
  table(
    columns: (1.1fr, 3.8fr),
    inset: 6pt,
    stroke: 0.4pt + luma(205),
    fill: (_, row) => if row == 0 { rgb("e7f0f4") } else { none },
    [*符号*], [*含义*],
    [$bold(x)_n$], [第 $n$ 个样本的 $p$ 维特征],
    [$y_n$], [第 $n$ 个样本的真实标签],
    [$hat(y)_n^((m-1))$], [前 $m-1$ 棵树给出的当前预测],
    [$f_m$], [准备加入的第 $m$ 棵回归树],
    [$R_j$], [第 $j$ 个叶节点覆盖的特征空间区域],
    [$w_j$], [第 $j$ 个叶节点给出的统一修正值],
    [$g_n,h_n$], [损失对当前预测的一阶、二阶导数],
    [$G_j,H_j$], [叶节点内 $g_n,h_n$ 的聚合量],
  ),
  caption: [核心符号表],
)

#key-box([先区分两种权重], [
  本文的 $w_j$ 是树叶节点的输出，不是投资组合权重。LightGBM 先生成股票预测分数，Qlib 的交易策略再把分数转换成持仓权重。两者属于不同阶段。
])

= 第一步：增加第 $m$ 棵树

== 已有模型

已有 $m-1$ 棵树时，模型为

$
F_(m-1)(bold(x)) = sum_(q=1)^(m-1) f_(q)(bold(x)).
$

第 $n$ 个样本的当前预测是

$
hat(y)_n^((m-1)) = F_(m-1)(bold(x)_n).
$

现在加入第 $m$ 棵树：

$
F_(m)(bold(x)) = F_(m-1)(bold(x)) + eta f_(m)(bold(x)),
$

其中 $eta in (0,1]$ 是学习率。为了看清主干推导，下面先令 $eta=1$；最后再把学习率乘回去。

== 一棵树的两个未知部分

具有 $J$ 个叶节点的回归树可以写成

$
f_(m)(bold(x))
= sum_(j=1)^J w_j bb(1)(bold(x) in R_j).
$

这里确实有两类未知量：

- 树结构：$R_1,dots,R_J$；
- 叶节点输出：$w_1,dots,w_J$。

如果 $bold(x)_n in R_j$，则

$
f_(m)(bold(x)_n)=w_j,
$

所以新预测为

$
hat(y)_n^((m)) = hat(y)_n^((m-1)) + w_j.
$

#intuition([
  $R_j$ 回答“哪些样本放在一起”，$w_j$ 回答“这组样本统一修正多少”。LightGBM 并不全局同时枚举所有树，而是贪心构造 $R_j$；一旦某个候选区域确定，$w_j$ 可以解析求出。
])

= 第二步：从损失函数得到 $g$ 和 $h$

== 第 $m$ 轮的原始目标

加入新树以后，希望最小化

$
cal(L)^((m))
= sum_(n=1)^N
  ell(y_n, hat(y)_n^((m-1)) + f_(m)(bold(x)_n))
  + Omega(f_m).
$

常见的树复杂度正则项是

$
Omega(f_m)
= gamma J + frac(lambda, 2) sum_(j=1)^J w_j^2.
$

直接优化这个式子困难，因为树结构是离散对象。LightGBM 的关键动作是：在当前预测 $hat(y)_n^((m-1))$ 附近，把每个样本的损失写成关于“新增修正量” $f_(m)(bold(x)_n)$ 的二次函数。

== 一阶导数 $g_n$

对第 $n$ 个样本，把损失写成当前预测 $z$ 的函数：

$
L_(n)(z) = ell(y_n,z).
$

当前所在位置是

$
z = hat(y)_n^((m-1)).
$

定义一阶导数

$
g_n
= frac(partial ell(y_n,hat(y)_n), partial hat(y)_n)
  |_(hat(y)_n = hat(y)_n^((m-1))).
$

$g_n$ 是损失曲线在当前位置的斜率。若 $g_n>0$，增加预测会增加损失，应向下修正；若 $g_n<0$，增加预测会降低损失，应向上修正。因此真正的下降方向是 $-g_n$。

== 二阶导数 $h_n$

定义二阶导数

$
h_n
= frac(partial^2 ell(y_n,hat(y)_n), partial hat(y)_n^2)
  |_(hat(y)_n = hat(y)_n^((m-1))).
$

$h_n$ 描述损失曲线的局部曲率：它衡量梯度随预测值变化得有多快。在一维牛顿法中，局部最优修正是

$
Delta^star = - frac(g,h).
$

这已经预告了 LightGBM 叶节点输出公式为什么会出现“梯度和除以 Hessian 和”。

== 二阶泰勒展开

设新增修正量为

$
Delta_n=f_(m)(bold(x)_n).
$

在当前预测处做二阶泰勒展开：

$
ell(y_n,hat(y)_n^((m-1))+Delta_n)
approx
ell(y_n,hat(y)_n^((m-1)))
+g_n Delta_n
+frac(1,2) h_n Delta_n^2.
$

去掉与新树无关的常数项后，第 $m$ 棵树要优化

$
tilde(cal(L))^((m))
= sum_(n=1)^N
  [g_n f_(m)(bold(x)_n)
  + frac(1,2)h_n f_(m)(bold(x)_n)^2]
  + Omega(f_m).
$

#key-box([$g,h$ 的最短解释], [
  $g_n$ 给出第 $n$ 个样本应该向哪个方向修正；$h_n$ 给出损失在当前位置有多弯，从而缩放修正步长。二者只是损失函数局部二次近似的两个系数。
])

= 平方损失下，$g$ 和 $h$ 就是残差语言

== 直接求导

采用带 $1/2$ 的平方损失：

$
ell(y_n,hat(y)_n)
= frac(1,2)(y_n-hat(y)_n)^2.
$

一阶导数是

$
g_n
= hat(y)_n^((m-1))-y_n.
$

定义当前残差

$
r_n = y_n-hat(y)_n^((m-1)),
$

则

$
(g_n=-r_n).
$

二阶导数是

$
(h_n=1).
$

因此平方损失下，负梯度就是残差：

$
-g_n=r_n=y_n-hat(y)_n^((m-1)).
$

== 不用泰勒公式也能看见它们

加入新树修正 $Delta_n=f_(m)(bold(x)_n)$ 后，新的残差为

$
r_n-Delta_n.
$

平方损失可以精确展开为

$
frac(1,2)(r_n-Delta_n)^2
= frac(1,2)r_n^2-r_n Delta_n+frac(1,2)Delta_n^2.
$

又因为

$
g_n=-r_n, quad h_n=1,
$

所以

$
frac(1,2)(r_n-Delta_n)^2
= underbrace(frac(1,2)r_n^2, "旧模型常数")
+g_n Delta_n
+frac(1,2)h_n Delta_n^2.
$

#intuition([
  对平方损失，二阶展开不是近似，而是精确等式。此时可以完全忘掉抽象的 Hessian：$g_n$ 就是负残差，$h_n$ 恒为 $1$。
])

= 第三步：节点目标函数从哪里来

== 把属于同一叶节点的样本放在一起

设第 $j$ 个叶节点包含的样本索引集合为

$
I_j={n: bold(x)_n in R_j}.
$

对于所有 $n in I_j$，树的输出都相同：

$
f_(m)(bold(x)_n)=w_j.
$

因此这些样本对二阶近似目标的贡献为

$
sum_(n in I_j)
  [g_n w_j+frac(1,2)h_n w_j^2].
$

定义节点聚合量

$
(G_j=sum_(n in I_j)g_n),
quad
(H_j=sum_(n in I_j)h_n).
$

因为同一节点内的 $w_j$ 是共同常数，所以可以提出求和号：

$
sum_(n in I_j)g_n w_j=G_j w_j,
$

$
sum_(n in I_j)frac(1,2)h_n w_j^2
=frac(1,2)H_j w_j^2.
$

再加入 L2 正则项 $lambda w_j^2/2$，得到第 $j$ 个节点的目标函数：

$
(
  tilde(cal(L))_(j)(w_j)
  =G_j w_j+frac(1,2)(H_j+lambda)w_j^2
).
$

整棵树的目标是

$
tilde(cal(L))^((m))
= sum_(j=1)^J
  [G_j w_j+frac(1,2)(H_j+lambda)w_j^2]
  +gamma J.
$

== 求最优叶节点输出 $w_j$

给定区域 $R_j$ 后，$G_j,H_j$ 已知。对节点目标求导：

$
frac(partial tilde(cal(L))_(j), partial w_j)
=G_j+(H_j+lambda)w_j.
$

令导数等于零：

$
G_j+(H_j+lambda)w_j=0.
$

得到

$
(w_j^star=-frac(G_j,H_j+lambda)).
$

平方损失下，$g_n=-r_n$、$h_n=1$，所以

$
G_j=-sum_(n in I_j)r_n,
quad
H_j=|I_j|.
$

于是

$
w_j^star
=frac(sum_(n in I_j)r_n, |I_j|+lambda).
$

当 $lambda=0$ 时：

$
(
  w_j^star
  =frac(1,|I_j|)sum_(n in I_j)
   (y_n-hat(y)_n^((m-1)))
).
$

也就是说，叶节点输出就是该节点内的平均残差。

#key-box([节点目标函数的来源], [
  节点目标函数不是额外假设。它来自三步：先在当前预测处对每个样本的损失做二阶展开；再利用同一叶节点的样本共享 $w_j$；最后把节点内的 $g_n,h_n$ 分别求和为 $G_j,H_j$。
])

= 从节点最优值到 Gain

== 一个节点的最优得分

将

$
w_j^star=-frac(G_j,H_j+lambda)
$

代回节点目标：

$
tilde(cal(L))_(j)(w_j^star)
=-frac(1,2)frac(G_j^2,H_j+lambda).
$

定义节点能够带来的目标下降量为

$
"Score"(I_j)=frac(1,2)frac(G_j^2,H_j+lambda).
$

注意符号关系：最优目标贡献是 $-"Score"$，所以 $"Score"$ 越大，节点通过独立输出 $w_j$ 能降低的损失越多。

== 一个候选分裂的 Gain

设父节点 $I_P$ 被候选条件 $x^((k)) <= s$ 分成

$
I_L={n in I_P:x_n^((k))<=s},
$

$
I_R={n in I_P:x_n^((k))>s}.
$

统计量满足

$
G_P=G_L+G_R,
quad
H_P=H_L+H_R.
$

分裂收益等于“两个子节点的最优得分”减去“父节点的最优得分”，再减去新增叶节点的复杂度代价：

$
(
"Gain"(k,s)
=frac(1,2)[
  frac(G_L^2,H_L+lambda)
  +frac(G_R^2,H_R+lambda)
  -frac(G_P^2,H_P+lambda)
]-gamma
).
$

LightGBM 在候选特征和阈值中选择

$
(k^star,s^star)=arg max_(k,s) "Gain"(k,s).
$

由这个最佳切分得到两个新区域：

$
R_L=R_P inter {bold(x):x^((k^star))<=s^star},
$

$
R_R=R_P inter {bold(x):x^((k^star))>s^star}.
$

递归分裂后，每个叶节点区域都是路径上若干切分条件的交集：

$
R_j=inter.big_(q in cal(P)_j)
{bold(x):x^((k_q))<=s_q " 或 " x^((k_q))>s_q}.
$

因此，$R_j$ 不是由一个连续方程解析求解，而是由最大 Gain 的贪心切分逐步生成。

= 一个完整的平方损失数值例子

设一个父节点中有四个样本。当前模型的预测与真实值形成残差

$
r=(3,2,-2,-3).
$

平方损失下

$
g=-r=(-3,-2,2,3),
quad h=(1,1,1,1).
$

暂令

$
lambda=0, quad gamma=0.
$

== 不分裂

父节点统计量为

$
G_P=-3-2+2+3=0,
quad H_P=4.
$

父节点最优输出：

$
w_P^star=-frac(0,4)=0.
$

父节点得分：

$
"Score"(I_P)=frac(1,2)frac(0^2,4)=0.
$

这说明正负残差在同一个节点中完全抵消，一个统一的 $w_P$ 无法同时修正它们。

== 候选分裂

假设某个特征阈值把样本分成

$
I_L:{g_1,g_2}=(-3,-2),
$

$
I_R:{g_3,g_4}=(2,3).
$

则

$
G_L=-5, quad H_L=2,
quad
G_R=5, quad H_R=2.
$

左右叶节点输出为

$
w_L^star=-frac(-5,2)=2.5,
quad
w_R^star=-frac(5,2)=-2.5.
$

Gain 为

$
"Gain"
=frac(1,2)[frac(25,2)+frac(25,2)-frac(0,4)]
=12.5.
$

#intuition([
  这个切分把“需要向上修正”的样本与“需要向下修正”的样本分开了。父节点内相互抵消的梯度，进入两个子节点后不再抵消，所以 Gain 很大。
])

= 完整算法：把各部分重新连起来

第 $m$ 轮训练一棵树时，可以按下面的顺序理解：

```text
输入：样本 (x_n, y_n)，已有模型 F_(m-1)

1. 计算当前预测
   y_hat_n = F_(m-1)(x_n)

2. 计算每个样本的局部损失信息
   g_n = d loss / d y_hat_n
   h_n = d² loss / d y_hat_n²

3. 从根节点开始，枚举候选特征和阈值
   对每个候选分裂聚合 G_L, H_L, G_R, H_R

4. 计算每个候选分裂的 Gain
   选择 Gain 最大的分裂，生成新的区域 R_L, R_R

5. 按 leaf-wise 规则继续分裂当前收益最大的叶节点
   直到叶节点数、深度、最小样本数或最小 Gain 触发停止

6. 对每个最终区域 R_j 计算
   w_j = -G_j / (H_j + lambda)

7. 得到新树
   f_m(x) = sum_j w_j 1(x in R_j)

8. 更新模型
   F_m(x) = F_(m-1)(x) + eta f_m(x)
```

需要注意，算法在搜索切分时已经把候选子节点的最优 $w_L,w_R$ 代入目标，因此它能够比较不同候选区域“各自使用最优叶值以后”能降低多少损失。

= 学习率、正则化与停止条件

== 学习率

树计算出的叶节点值是 $w_j$，但模型实际加入的是

$
eta w_j.
$

因此

$
hat(y)_n^((m))
=hat(y)_n^((m-1))+eta w_j,
quad bold(x)_n in R_j.
$

较小的 $eta$ 让每棵树只完成一部分修正，通常需要更多树，但能降低过拟合风险。

== L2 正则化

$lambda$ 出现在分母中：

$
w_j^star=-frac(G_j,H_j+lambda).
$

当 $lambda$ 增大时，叶节点输出绝对值被压缩。它也会降低小样本叶节点的 Gain，使树更保守。

== 结构约束

LightGBM 还通过以下约束控制区域 $R_j$ 的复杂度：

- `num_leaves`：限制叶节点总数 $J$；
- `max_depth`：限制从根到叶的路径长度；
- `min_data_in_leaf`：要求 $|I_j|$ 不得过小；
- `min_gain_to_split`：要求候选 Gain 足够大；
- `feature_fraction`、`bagging_fraction`：随机使用部分特征或样本。

#pagebreak()
= 与 Qlib 股票预测的对应关系

在当前 Qlib LightGBM 工作流中，可以把数学对象对应为：

#figure(
  table(
    columns: (1.6fr, 3.4fr),
    inset: 6pt,
    stroke: 0.4pt + luma(205),
    fill: (_, row) => if row == 0 { rgb("e7f0f4") } else { none },
    [*数学对象*], [*Qlib 中的含义*],
    [$bold(x)_(i,t)$], [股票 $i$ 在交易日 $t$ 的 Alpha158 因子],
    [$y_(i,t)$], [配置文件定义的未来收益标签],
    [$hat(y)_(i,t)$], [LightGBM 输出的股票预测分数],
    [$R_j$], [满足一组因子阈值条件的股票-日期样本集合],
    [$w_j$], [该样本集合在当前 Boosting 轮次中的统一分数修正],
    [$f_m$], [第 $m$ 棵树对全部股票-日期样本的修正函数],
  ),
  caption: [数学对象与 Qlib 工作流的对应],
)

LightGBM 最终输出

$
hat(y)_(i,t)=F_(M)(bold(x)_(i,t)).
$

Qlib 再按同一天的预测分数排序，并由 TopK 等策略生成投资组合。树的 $w_j$ 并不是最终持仓权重。

= 容易混淆的三个问题

== LightGBM 是否同时求 $w$ 和 $R$

从优化目标看，它们都是未知量：

$
min_({R_j},{w_j}) cal(L).
$

但实际算法不做全局联合求解。它对每个候选分裂解析计算最优叶值，再用 Gain 贪心选择切分。可以概括为：

$
"候选 " R
arrow.r
"解析最优 " w
arrow.r
"计算 Gain"
arrow.r
"选择最佳 " R.
$

== $g,h$ 是模型参数吗

不是。$g_n,h_n$ 是当前轮次中，每个样本的损失函数局部信息。模型更新后，它们会重新计算。平方损失下：

$
g_n=hat(y)_n-y_n,
quad h_n=1.
$

== Gain 是熵或基尼指数吗

不是。LightGBM 回归树的 Gain 是二阶近似目标函数的下降量。它由 $G,H$ 决定，而不是分类树中的信息熵。

= 一页公式总结

#key-box([模型], [
  $
  F_(m)(bold(x))=F_(m-1)(bold(x))+eta f_(m)(bold(x)),
  $
  $
  f_(m)(bold(x))=sum_(j=1)^J w_j bb(1)(bold(x) in R_j).
  $
])

#key-box([样本梯度与 Hessian], [
  $
  g_n=frac(partial ell,partial hat(y)_n),
  quad
  h_n=frac(partial^2 ell,partial hat(y)_n^2).
  $
  平方损失下：$g_n=hat(y)_n-y_n=-r_n$，$h_n=1$。
])

#key-box([节点聚合与目标], [
  $
  G_j=sum_(n in I_j)g_n,
  quad
  H_j=sum_(n in I_j)h_n,
  $
  $
  tilde(cal(L))_(j)(w_j)
  =G_j w_j+frac(1,2)(H_j+lambda)w_j^2.
  $
])

#key-box([最优叶节点输出], [
  $
  (w_j^star=-frac(G_j,H_j+lambda)).
  $
  平方损失且 $lambda=0$ 时，$w_j^star$ 是节点内平均残差。
])

#key-box([分裂收益], [
  $
  (
  "Gain"
  =frac(1,2)[
    frac(G_L^2,H_L+lambda)
    +frac(G_R^2,H_R+lambda)
    -frac(G_P^2,H_P+lambda)
  ]-gamma
  ).
  $
])

#v(6mm)
#align(center)[
  #text(size: 9pt, fill: luma(110))[
    结论：平方损失下，LightGBM 每轮寻找能把不同残差模式分开的树区域，并用区域内平均残差修正已有模型。
  ]
]
